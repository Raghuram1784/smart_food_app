import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:socket_io_client/socket_io_client.dart' as io;
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/operations_screen.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real multi-role operations with live customer notifications', (
    tester,
  ) async {
    const id = String.fromEnvironment('EVIDENCE_ORDER_ID');
    const base = String.fromEnvironment(
      'API_BASE_URL',
      defaultValue: 'http://10.0.2.2:5000/api/v1/',
    );
    final passwords = {
      'customer': const String.fromEnvironment('DEMO_CUSTOMER_PASSWORD'),
      'restaurant': const String.fromEnvironment('DEMO_RESTAURANT_PASSWORD'),
      'rider': const String.fromEnvironment('DEMO_RIDER_PASSWORD'),
      'admin': const String.fromEnvironment('DEMO_ADMIN_PASSWORD'),
    };
    final prefs = await SharedPreferences.getInstance();
    await SecureTokenStorage().delete();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
        child: const FoodApp(),
      ),
    );
    await tester.pumpAndSettle();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(FoodApp)),
    );
    final router = GoRouter.of(tester.element(find.byType(Scaffold).first));
    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 150; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) return;
      }
      expect(finder, findsWidgets);
    }

    Future<void> login(String role, String route) async {
      await container.read(authProvider.future);
      if (container.read(authProvider).asData?.value != null)
        await container.read(authProvider.notifier).logout();
      await container
          .read(authProvider.notifier)
          .login('$role@demo.test', passwords[role]!);
      router.go(route);
      await tester.pumpAndSettle();
    }

    await login('customer', '/orders/$id');
    await waitFor(find.text('Order timeline'));
    // Separate authenticated customer socket verifies simultaneous notifications during UI role switching.
    final external = Dio(BaseOptions(baseUrl: base));
    final loginResult = (await external.post(
      'auth/login',
      data: {'email': 'customer@demo.test', 'password': passwords['customer']},
    )).data['data'];
    final token = loginResult['session']['token'];
    external.options.headers['Authorization'] = 'Bearer $token';
    final connected = Completer<void>(), events = <Map>[];
    final socket = io.io(
      Uri.parse(base).origin,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .enableForceNew()
          .disableAutoConnect()
          .setAuth({'token': token})
          .build(),
    );
    socket.onConnect((_) {
      if (!connected.isCompleted) connected.complete();
    });
    socket.on('order.updated', (e) {
      if (e['orderId'] == id) events.add(Map.from(e));
    });
    socket.connect();
    await tester.runAsync(
      () => connected.future.timeout(const Duration(seconds: 15)),
    );
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    Future<void> screenshot(String name) async {
      await tester.pumpAndSettle();
      await binding.takeScreenshot(name);
    }

    Future<void> press(String label) async {
      final button = find.text(label);
      await waitFor(button);
      await tester.scrollUntilVisible(
        button,
        180,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      await tester.tap(button);
      await tester.pumpAndSettle();
    }

    Future<void> status(String expected) async {
      for (var i = 0; i < 80; i++) {
        final o = (await external.get('orders/$id')).data['data'];
        if (o['status'] == expected) return;
        await tester.pump(const Duration(milliseconds: 100));
      }
      fail('Order did not reach $expected');
    }

    try {
      await screenshot('01-customer-pending');
      await login('restaurant', '/inbox/deccan-handi-gachi/orders/$id');
      await waitFor(find.text('Accept'));
      await screenshot('02-owner-actions');
      await press('Accept');
      await status('ACCEPTED');
      await press('Start preparing');
      await status('PREPARING');
      await screenshot('03-kitchen-preparing');
      await press('Mark ready');
      await status('READY_FOR_PICKUP');
      await login('admin', '/dispatch');
      await waitFor(find.textContaining('Assign Demo Delivery'));
      await press('Assign Demo Delivery Partner');
      await screenshot('04-admin-assigned');
      await login('rider', '/deliveries');
      await waitFor(find.text('Confirm pickup'));
      await screenshot('05-rider-assignment');
      await press('Confirm pickup');
      await status('PICKED_UP');
      await press('Out for delivery');
      await status('OUT_FOR_DELIVERY');
      await screenshot('06-out-for-delivery');
      // Keep customer UI mounted while an independently authenticated rider submits final delivery.
      await login('customer', '/orders/$id');
      await waitFor(find.text('Out for delivery'));
      final rider = Dio(BaseOptions(baseUrl: base));
      final r = (await rider.post(
        'auth/login',
        data: {'email': 'rider@demo.test', 'password': passwords['rider']},
      )).data['data'];
      rider.options.headers['Authorization'] =
          'Bearer ${r['session']['token']}';
      final o = (await rider.get('operations/delivery/orders/$id'))
          .data['data'];
      await rider.post(
        'operations/delivery/orders/$id/deliver',
        data: {'expectedVersion': o['version']},
      );
      await waitFor(find.text('Delivered'));
      await screenshot('07-customer-live-delivered');
      await rider.post('auth/logout');
      rider.close();
      final result = (await external.get('orders/$id')).data['data'];
      expect(result['status'], 'DELIVERED');
      expect(result['paymentStatus'], 'UNPAID');
      expect(result['paymentMethod'], 'DEMO_NO_PAYMENT');
      for (final state in [
        'ACCEPTED',
        'PREPARING',
        'READY_FOR_PICKUP',
        'PICKED_UP',
        'OUT_FOR_DELIVERY',
        'DELIVERED',
      ]) {
        expect(
          events.any((e) => e['status'] == state),
          true,
          reason: 'Actual customer socket must receive $state',
        );
      }
      binding.reportData = {
        ...?binding.reportData,
        'orderId': id,
        'orderNumber': result['orderNumber'],
        'status': result['status'],
        'paymentStatus': result['paymentStatus'],
        'events': result['events'],
        'liveEvents': events,
        'devices': 'One Android emulator with sequential role switching; simultaneous independent authenticated customer socket',
      };
    } finally {
      socket.dispose();
      await external.post('auth/logout');
      external.close();
      await container.read(authProvider.notifier).logout();
      await tester.pumpWidget(const SizedBox());
    }
  }, timeout: const Timeout(Duration(minutes: 8)));
}
