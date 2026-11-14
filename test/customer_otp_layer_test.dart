import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/customer_handover_card.dart';
import 'package:smart_food_demo/features/commerce/customer_otp_layer.dart';
import 'package:smart_food_demo/features/commerce/live_orders.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'rider_dashboard_test.dart' show FakeOps;

const _pin = '482913';

FakeOps _customerWithActiveOtp() => FakeOps()
  ..orders = [
    {'id': 'order-9', 'status': 'READY_FOR_PICKUP'},
  ]
  ..handover = {
    'state': 'ACTIVE',
    'pin': _pin,
    'challengeVersion': 1,
    'expiresAt': DateTime.now().add(const Duration(minutes: 9)).toUtc().toIso8601String(),
    'attemptsRemaining': 5,
    'issuesRemaining': 2,
  };

/// Mirrors lib/app.dart exactly: the layer lives in MaterialApp.router's
/// `builder`, ABOVE the Navigator (the placement that crashed on the Samsung).
Future<(GoRouter, StreamController<LiveOrderUpdate>, FakeAuth)> _app(
  WidgetTester tester,
  FakeOps repo,
  String role, {
  Size size = const Size(360, 740),
  double textScale = 1.5,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final live = StreamController<LiveOrderUpdate>.broadcast();
  addTearDown(live.close);
  final auth = FakeAuth()..saved = session(role);
  addTearDown(auth.events.close);
  Widget page(String name) => Scaffold(appBar: AppBar(title: Text(name)), body: Center(child: Text('$name body')));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => page('Home')),
    GoRoute(path: '/search', builder: (_, _) => page('Search')),
    GoRoute(path: '/restaurant/tiffin', builder: (_, _) => page('Restaurant')),
    GoRoute(path: '/cart', builder: (_, _) => page('Cart')),
    GoRoute(path: '/orders', builder: (_, _) => page('Orders')),
    GoRoute(path: '/account', builder: (_, _) => page('Account')),
    GoRoute(
      path: '/orders/:id',
      builder: (_, s) => Scaffold(
        appBar: AppBar(title: const Text('Order details')),
        body: ListView(children: [
          CustomerHandoverCard(order: {'id': s.pathParameters['id'], 'status': 'READY_FOR_PICKUP', 'version': 6}),
        ]),
      ),
    ),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(auth),
      commerceRepositoryProvider.overrideWithValue(repo),
      liveOrdersProvider.overrideWith((ref) => live.stream),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(textScale), padding: const EdgeInsets.only(top: 40, bottom: 24)),
      child: MaterialApp.router(
        routerConfig: router,
        builder: (context, child) => CustomerOtpLayer(
          navigatorKey: router.routerDelegate.navigatorKey,
          onOpenOrder: (id) => router.push('/orders/$id'),
          child: child ?? const SizedBox.shrink(),
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (router, live, auth);
}

void main() {
  testWidgets('customer re-login hydrates the active OTP into the ROOT overlay (no "No Overlay" crash), narrow + 1.5x text', (tester) async {
    final repo = _customerWithActiveOtp();
    await _app(tester, repo, 'CUSTOMER');
    expect(tester.takeException(), isNull, reason: 'no framework assertion (was: No Overlay widget found)');
    final popup = find.byKey(const ValueKey('customer-otp-popup'));
    expect(popup, findsOneWidget);
    expect(find.text(_pin), findsOneWidget);
    expect(find.text('Order FD-REAL-REF-9'), findsOneWidget);
    expect(find.textContaining('Valid for'), findsOneWidget);
    // The popup lives under an Overlay (the Navigator's), so tooltips work.
    expect(find.ancestor(of: popup, matching: find.byType(Overlay)), findsWidgets);
    await tester.longPress(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    // Fits inside the 360x740 viewport.
    final r = tester.getRect(popup);
    expect(r.left >= 0 && r.right <= 360 && r.top >= 0 && r.bottom <= 740, isTrue, reason: 'popup rect $r');
    // Reading never issues a new code.
    expect(repo.calls.where((c) => c.contains('/handover/issue')), isEmpty);
  });

  testWidgets('dismiss, recover from Order Details, navigate all customer routes without duplicates, logout removes it', (tester) async {
    final repo = _customerWithActiveOtp();
    final (router, live, _) = await _app(tester, repo, 'CUSTOMER', size: const Size(393, 852), textScale: 1);
    await tester.tap(find.text('Copy OTP'));
    await tester.pump();
    expect(find.text('Copied'), findsOneWidget);
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-otp-popup')), findsNothing);

    // Recover from Order Details (the card reads the same authorized endpoint).
    router.push('/orders/order-9');
    await tester.pumpAndSettle();
    expect(find.text(_pin), findsOneWidget);
    expect(find.byKey(const ValueKey('customer-otp-popup')), findsNothing, reason: 'dismissed code does not re-pop');

    for (final path in ['/', '/search', '/restaurant/tiffin', '/cart', '/orders', '/account']) {
      router.go(path);
      await tester.pumpAndSettle();
      // A reconnect re-scans; the dismissed code must not duplicate.
      live.add(const LiveOrderUpdate('Live updates connected', reconcile: true));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('customer-otp-popup')), findsNothing);
      expect(tester.takeException(), isNull);
    }

    // A re-issued code (new challenge version) appears once, on whatever screen is open.
    repo.handover = {...repo.handover, 'pin': '715002', 'challengeVersion': 2};
    live.add(const LiveOrderUpdate('Live updates connected', orderId: 'order-9', eventType: 'HANDOVER_ISSUED_2'));
    live.add(const LiveOrderUpdate('Live updates connected', orderId: 'order-9', eventType: 'HANDOVER_ISSUED_2'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-otp-popup')), findsOneWidget);
    expect(find.text('715002'), findsOneWidget);

    // Logout removes the popup immediately.
    final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('customer-otp-popup')), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rider/owner/admin sessions never read or display a customer OTP', (tester) async {
    for (final role in ['DELIVERY_PARTNER', 'RESTAURANT_OWNER', 'ADMIN']) {
      final repo = _customerWithActiveOtp();
      final (_, live, _) = await _app(tester, repo, role);
      live.add(const LiveOrderUpdate('Live updates connected', orderId: 'order-9', eventType: 'HANDOVER_ISSUED_1'));
      live.add(const LiveOrderUpdate('Live updates connected', reconcile: true));
      await tester.pumpAndSettle();
      expect(find.text(_pin), findsNothing, reason: role);
      expect(repo.calls.where((c) => c.contains('handover') || c.startsWith('GET orders')), isEmpty, reason: role);
      await tester.pumpWidget(const SizedBox());
    }
  });
}
