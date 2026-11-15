import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/live_orders.dart';
import 'package:smart_food_demo/features/operations/rider_dashboard_screen.dart';
import 'package:smart_food_demo/features/operations/rider_presence_provider.dart';

import 'auth_test.dart' show FakeAuth, session;

/// Minimal backend fake for the rider and customer OTP flows.
class FakeOps implements CommerceRepository {
  bool online = false;
  bool onDelivery = false;
  final calls = <String>[];
  List<Json> offers = [
    {
      'id': 'offer-1',
      'orderId': 'order-9',
      'orderNumber': 'FD-REAL-REF-9',
      'restaurantName': 'The Tiffin Room',
      'pickupAddress': 'Madhapur, Hyderabad',
      'dropArea': 'Kondapur',
      'items': [
        {'name': 'Ghee Roast Dosa', 'quantity': 2},
      ],
      'orderTotalPaise': 32000,
    },
  ];
  List<Json> orders = [];
  Json handover = {'state': 'NOT_ISSUED'};

  Json get _presence => {
    'isOnline': online,
    'isAvailable': online && !onDelivery,
    'activeAssignment': onDelivery ? {'id': 'a1', 'orderId': 'order-9', 'status': 'READY_FOR_PICKUP'} : null,
  };

  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    calls.add('$method $path');
    if (path == 'rider/presence/me') return _presence;
    if (path == 'rider/presence/online') {
      online = true;
      return _presence;
    }
    if (path == 'rider/presence/offline') {
      online = false;
      return _presence;
    }
    if (path == 'operations/delivery/offers') {
      return {'available': online && !onDelivery, 'offers': online && !onDelivery ? offers : <Json>[]};
    }
    if (path.endsWith('/accept')) {
      onDelivery = true;
      offers = [];
      orders = [
        {'id': 'order-9', 'orderNumber': 'FD-REAL-REF-9', 'restaurantName': 'The Tiffin Room', 'status': 'READY_FOR_PICKUP', 'version': 6, 'paymentStatus': 'PAID', 'finalPayablePaise': 32000, 'items': <Json>[], 'availableActions': ['pickup'], 'createdAt': '2026-11-16T10:00:00Z'},
      ];
      return {'orderId': 'order-9', 'otpIssued': true};
    }
    if (path.endsWith('/decline')) {
      offers = [];
      return {'declined': true};
    }
    if (path.startsWith('operations/delivery/orders')) return {'items': orders, 'total': orders.length, 'page': 1};
    if (path.startsWith('orders?')) return {'items': orders, 'total': orders.length};
    if (path.endsWith('/handover')) return handover;
    if (path.startsWith('orders/')) return {'id': path.split('/')[1], 'orderNumber': 'FD-REAL-REF-9'};
    throw StateError('unexpected $method $path');
  }

  @override
  Future<Json?> pending(String userId) async => null;
  @override
  Future<Json> place(String userId, Json input) => throw UnimplementedError();
  @override
  Future<void> forgetPending(String userId) async {}
}

Future<(ProviderContainer, StreamController<LiveOrderUpdate>)> _mount(
  WidgetTester tester,
  FakeOps repo,
  String role,
  Widget child,
) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final live = StreamController<LiveOrderUpdate>.broadcast();
  addTearDown(live.close);
  // Tree-owned scope: providers (and their timers) are disposed with the widget tree.
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session(role)),
      commerceRepositoryProvider.overrideWithValue(repo),
      liveOrdersProvider.overrideWith((ref) => live.stream),
    ],
    child: MaterialApp(home: child),
  ));
  await tester.pumpAndSettle();
  final container = ProviderScope.containerOf(tester.element(find.byType(MaterialApp)));
  return (container, live);
}

void main() {
  testWidgets('rider dashboard: GPS-free toggle, persisted request popup, accept, tabs, no red screen', (tester) async {
    final repo = FakeOps();
    final (container, live) = await _mount(tester, repo, 'DELIVERY_PARTNER', const RiderDashboardScreen());
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Go Online'), findsOneWidget);
    expect(find.textContaining('GPS'), findsNothing);
    expect(find.textContaining('°'), findsNothing, reason: 'no coordinates shown');

    await tester.tap(find.text('Go Online'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('POST rider/presence/online'));
    expect(find.text('Online & available'), findsOneWidget);
    // The persisted request is announced once as a popup with real backend fields.
    expect(find.text('New Delivery Request'), findsOneWidget);
    expect(find.text('Restaurant: The Tiffin Room'), findsOneWidget);
    expect(find.text('Order: FD-REAL-REF-9'), findsOneWidget);
    expect(find.text('Items: 2 × Ghee Roast Dosa'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Accept Delivery').last);
    await tester.pumpAndSettle();
    expect(repo.calls, contains('POST operations/delivery/offers/offer-1/accept'));
    expect(find.text('On a delivery'), findsOneWidget);
    expect(find.text('New delivery requests'), findsNothing, reason: 'busy riders get no new requests');
    expect(find.text('Confirm pickup'), findsOneWidget);

    for (final tab in ['In Transit (0)', 'History (0)', 'All (1)', 'Assigned (1)']) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    }
    // Socket nudges just trigger a fresh API read.
    live.add(const LiveOrderUpdate('Live updates connected', offersChanged: true));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // Logout resets presence state.
    await container.read(authProvider.notifier).logout();
    await tester.pumpAndSettle();
    expect(container.read(riderPresenceProvider).isOnline, isFalse);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('decline from the popup; offline rider sees no requests', (tester) async {
    final repo = FakeOps()..online = true;
    await _mount(tester, repo, 'DELIVERY_PARTNER', const RiderDashboardScreen());
    await tester.tap(find.widgetWithText(TextButton, 'Decline'));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('POST operations/delivery/offers/offer-1/decline'));
    expect(find.textContaining('Waiting for new delivery requests'), findsOneWidget);
    await tester.tap(find.text('Go Offline'));
    await tester.pumpAndSettle();
    expect(find.text('New delivery requests'), findsNothing);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
  // Global customer OTP layer tests live in customer_otp_layer_test.dart,
  // mounted in the real MaterialApp.router builder placement.

  testWidgets('two pending requests: each gets its own popup, one after another', (tester) async {
    final repo = _TwoOffers()..online = true;
    await _mount(tester, repo, 'DELIVERY_PARTNER', const RiderDashboardScreen());
    await tester.pumpAndSettle();
    expect(find.text('Order: FD-FIRST-1'), findsOneWidget);
    await tester.tap(find.descendant(of: find.byType(AlertDialog), matching: find.text('Decline')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('POST operations/delivery/offers/offer-a/decline'));
    expect(find.text('Order: FD-SECOND-2'), findsOneWidget, reason: 'the second request is announced too');
    await tester.tap(find.byKey(const ValueKey('offer-dialog-accept')));
    await tester.pumpAndSettle();
    expect(repo.calls, contains('POST operations/delivery/offers/offer-b/accept'));
    expect(tester.takeException(), isNull);
  });
}

class _TwoOffers extends FakeOps {
  _TwoOffers() {
    offers = [
      {'id': 'offer-a', 'orderId': 'order-a', 'orderNumber': 'FD-FIRST-1', 'restaurantName': 'The Tiffin Room', 'items': <Json>[], 'orderTotalPaise': 10000},
      {'id': 'offer-b', 'orderId': 'order-b', 'orderNumber': 'FD-SECOND-2', 'restaurantName': 'The Tiffin Room', 'items': <Json>[], 'orderTotalPaise': 12000},
    ];
  }
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.endsWith('/decline')) {
      calls.add('$method $path');
      offers = offers.where((o) => !path.contains(o['id'] as String)).toList();
      return {'declined': true};
    }
    return super.request(method, path, data);
  }
}
