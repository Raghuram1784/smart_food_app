import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/tracking/rider_location_sharing.dart';

/// F4 on one Samsung: the phone is the RIDER sharing its own real hardware GPS (the app never
/// simulates positions), then the same phone switches to the CUSTOMER tracking screen. Kitchen and
/// pickup/OTP actions use the authorized REST APIs. This does not prove two-phone physical tracking.
void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('Samsung live rider GPS, screen-off sharing, customer map and termination after OTP', (tester) async {
    const base = String.fromEnvironment('API_BASE_URL'); const password = String.fromEnvironment('F3_PASSWORD'); const rid = String.fromEnvironment('F3_RESTAURANT'); const dish = String.fromEnvironment('F3_DISH');
    const emails = {'customer': String.fromEnvironment('F3_CUSTOMER_EMAIL'), 'owner': String.fromEnvironment('F3_OWNER_EMAIL'), 'rider': String.fromEnvironment('F3_RIDER_EMAIL')};
    final clients = <String, Dio>{};
    for (final role in emails.keys) {
      final d = Dio(BaseOptions(baseUrl: base));
      final auth = (await d.post('auth/login', data: {'email': emails[role], 'password': password})).data['data'];
      d.options.headers['Authorization'] = 'Bearer ${auth['session']['token']}';
      clients[role] = d;
    }
    final customer = clients['customer']!, owner = clients['owner']!, rider = clients['rider']!;
    // Synthetic test account address with a confirmed test pin (test data, not app-generated coordinates).
    final address = (await customer.post('addresses', data: {'label': 'F4 test pin', 'recipientName': 'NeuroX Demo', 'contactNumber': '9000000000', 'addressLine1': '2 Synthetic Test Lane', 'localityId': 'madhapur', 'postalCode': '500081', 'isDefault': true,
      'latitude': 17.4483, 'longitude': 78.3915, 'locationAccuracyMeters': 10, 'locationSource': 'CUSTOMER_MAP_PIN'})).data['data'];
    var cart = (await customer.get('cart')).data['data'];
    if ((cart['items'] as List? ?? []).isNotEmpty) cart = (await customer.delete('cart', data: {'expectedVersion': cart['version']})).data['data'];
    cart = (await customer.post('cart/items', data: {'restaurantId': rid, 'menuItemId': dish, 'quantity': 1, 'addOnIds': [], 'expectedVersion': cart['version']})).data['data'];
    final quote = Json.from((await customer.post('cart/quote', data: {'addressId': address['id'], 'expectedVersion': cart['version']})).data['data']);

    await SecureTokenStorage().delete();
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(ProviderScope(overrides: [preferencesProvider.overrideWithValue(prefs)], child: const FoodApp()));
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(tester.element(find.byType(FoodApp)));
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    Future<void> pause([int s = 1]) async { await tester.runAsync(() => Future<void>.delayed(Duration(seconds: s))); await tester.pump(); }
    Future<void> login(String role, String path) async {
      await container.read(authProvider.future);
      if (container.read(authProvider).asData?.value != null) await container.read(authProvider.notifier).logout();
      await container.read(authProvider.notifier).login(emails[role]!, password);
      router.go(path);
      await tester.pumpAndSettle();
    }
    Future<void> waitFor(Finder f, {int seconds = 30}) async { for (var i = 0; i < seconds * 10; i++) { await tester.pump(const Duration(milliseconds: 100)); if (f.evaluate().isNotEmpty) return; } expect(f, findsWidgets); }
    Future<void> shot(String name) async { await tester.pump(const Duration(milliseconds: 300)); await binding.takeScreenshot(name); }
    Future<Json> transition(Dio c, String scope, String id, String action) async {
      for (var i = 0; i < 60; i++) {
        final cur = (await c.get('operations/$scope/orders/$id')).data['data'];
        final r = await c.post('operations/$scope/orders/$id/$action', data: {'expectedVersion': cur['version']}, options: Options(validateStatus: (_) => true));
        if (r.statusCode == 200) return Json.from(r.data['data']);
        expect(r.statusCode, 409);
        await pause();
      }
      throw StateError('transition $action unavailable');
    }
    Future<Json> track() async => Json.from((await customer.get('tracking/orders/$id0')).data['data']);

    // 1) Customer places an IMMEDIATE order through the real checkout screen.
    await login('customer', '/cart');
    router.go('/checkout', extra: {...quote, 'addressId': address['id']});
    await tester.pumpAndSettle();
    await binding.convertFlutterSurfaceToImage();
    await tester.tap(find.byKey(const ValueKey('place-order')));
    await tester.pumpAndSettle();
    await waitFor(find.text('Order confirmation'));
    final order = Json.from(((await customer.get('orders')).data['data']['items'] as List).first);
    id0 = order['id'] as String;
    expect(order['deliveryMode'], 'NOW');

    // 2) Kitchen, then GPS-free dispatch: rider goes online WITHOUT location and accepts in the UI.
    await transition(owner, 'restaurant', id0, 'accept');
    await transition(owner, 'restaurant', id0, 'start-preparing');
    await transition(owner, 'restaurant', id0, 'ready');
    await rider.post('rider/presence/online', data: {});
    for (var i = 0; i < 60; i++) { final offers = (await rider.get('operations/delivery/offers')).data['data']['offers'] as List; if (offers.any((o) => o['orderId'] == id0)) break; await pause(); }
    await login('rider', '/deliveries');
    // Other synthetic invitations may be pending in the shared dev DB: decline those, accept only ours.
    final accept = find.byKey(const ValueKey('offer-dialog-accept'));
    for (var attempt = 0; attempt < 8; attempt++) {
      await waitFor(accept);
      final ours = find.descendant(of: find.byType(AlertDialog), matching: find.text('Order: ${order['orderNumber']}')).evaluate().isNotEmpty;
      if (ours) {
        await tester.tap(accept);
        await tester.pumpAndSettle();
        break;
      }
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Decline')));
      await tester.pumpAndSettle();
      await pause();
    }
    var assigned = false;
    for (var i = 0; i < 30 && !assigned; i++) { await pause(); assigned = ((await rider.get('operations/delivery/orders')).data['data']['items'] as List).any((o) => o['id'] == id0); }
    expect(assigned, isTrue);
    final view0 = await track();
    expect(view0['rider']['freshness'], 'WAITING', reason: 'accepted without any GPS');

    // 3) Rider starts sharing; the OS permission prompt is answered on the phone (harness watcher).
    final panel = find.byKey(const ValueKey('rider-tracking-panel'));
    await waitFor(panel);
    for (var i = 0; i < 5 && find.byType(AlertDialog).evaluate().isNotEmpty; i++) {
      await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Decline')));
      await tester.pumpAndSettle();
    }
    final start = find.byKey(const ValueKey('rider-tracking-start'));
    if (start.evaluate().isNotEmpty) { await tester.ensureVisible(start); await tester.pumpAndSettle(); await tester.tap(start); }
    debugPrint('F4_PERMISSION_WINDOW');
    Json? v;
    for (var i = 0; i < 120; i++) {
      await pause();
      v = await track();
      if (v['rider']['location'] != null) break;
    }
    expect(v!['rider']['location'], isNotNull, reason: 'real GPS fix from the phone reached the server');
    final firstFix = DateTime.parse(v['rider']['location']['recordedAt'] as String);
    final accuracy = (v['rider']['location']['accuracyMeters'] as num).toDouble();
    expect(container.read(riderLocationSharingProvider).status, SharingStatus.sharing);
    await shot('01-rider-sharing-live-location');

    // 4) Screen off for ~45 s (harness watcher): fixes must keep arriving via the foreground service.
    debugPrint('F4_SCREEN_OFF_WINDOW');
    final during = <DateTime>{};
    for (var i = 0; i < 55; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(seconds: 1)));
      final loc = (await track())['rider']['location'];
      if (loc != null) during.add(DateTime.parse(loc['recordedAt'] as String));
    }
    final screenOffFixes = during.where((t) => t.isAfter(firstFix)).length;
    expect(screenOffFixes, greaterThanOrEqualTo(2), reason: 'location kept flowing with the screen off');
    await tester.pump();

    // 5) Same phone becomes the customer: live map with the rider's real position.
    await transition(rider, 'delivery', id0, 'pickup');
    await transition(rider, 'delivery', id0, 'out-for-delivery');
    await login('customer', '/orders/$id0/track');
    await waitFor(find.byKey(const ValueKey('rider-marker')), seconds: 45);
    final live = await track();
    await shot('02-customer-live-tracking-map');
    await waitFor(find.byKey(const ValueKey('eta-card')));

    // 6) OTP delivery ends tracking: server refuses further fixes; customer view shows Delivered.
    final pin = (await customer.get('orders/$id0/handover')).data['data']['pin'];
    final cur = (await rider.get('operations/delivery/orders/$id0')).data['data'];
    final done = Json.from((await rider.post('operations/delivery/orders/$id0/complete-handover', data: {'pin': pin, 'expectedVersion': cur['version']})).data['data']);
    expect(done['status'], 'DELIVERED');
    final after = await rider.post('tracking/orders/$id0/location', data: {'latitude': 17.4483, 'longitude': 78.3915, 'accuracyMeters': 10, 'recordedAt': DateTime.now().toUtc().toIso8601String()}, options: Options(validateStatus: (_) => true));
    expect(after.statusCode, 410, reason: 'no tracking after OTP delivery');
    await pause(3);
    await waitFor(find.text('Delivered'));
    final ended = await track();
    expect(ended['trackingActive'], false);
    expect(ended['rider']['location'], isNull);
    await shot('03-customer-delivered-tracking-ended');

    binding.reportData = {
      'orderNumber': order['orderNumber'], 'device': 'Samsung S23 Ultra SM-S918B (single phone: rider, then customer)',
      'firstFixAccuracyMeters': accuracy.round(), 'fixesWhileScreenOff': screenOffFixes,
      'customerFreshnessAtCapture': live['rider']['freshness'], 'etaSource': live['eta']['source'], 'routingProvider': live['routing']['provider'],
      'postDeliveryFixStatus': after.statusCode, 'trackingActiveAfterDelivery': ended['trackingActive'],
      'flow': 'UI checkout (immediate), UI rider acceptance and live-location start, real phone GPS, screen-off via adb, UI customer map; kitchen/pickup/OTP via authorized REST',
    };
    for (final c in clients.values) { c.close(); }
  }, timeout: const Timeout(Duration(minutes: 12)));
}

String id0 = '';
