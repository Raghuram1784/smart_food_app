import 'package:smart_food_demo/features/auth/auth_repository.dart';

import 'auth_test.dart' show FakeAuth, session;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/live_orders.dart';
import 'package:smart_food_demo/features/commerce/operations_screen.dart';

import 'commerce_test.dart' show FakeCommerce;

Json order() => {
  'id': 'o',
  'orderNumber': 'FD-TEST',
  'restaurantName': 'Test Kitchen',
  'createdAt': '2026-11-13T08:00:00Z',
  'version': 1,
  'status': 'PENDING_RESTAURANT',
  'paymentStatus': 'PAID',
  'paymentEligible': true,
  'finalPayablePaise': 36400,
  'items': [
    {'name': 'Dosa', 'quantity': 1, 'addOns': []},
  ],
  'events': [],
  'availableActions': ['accept', 'reject'],
};

class OperationRepo extends FakeCommerce {
  Json current = order();
  Completer<dynamic>? pendingAction;
  int writes = 0, reads = 0;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (method == 'POST') {
      writes++;
      expect(data?['expectedVersion'], 1);
      return pendingAction!.future;
    }
    reads++;
    return current;
  }
}

void main() {
  test('duplicate and stale event versions are ignored', () {
    final versions = EventVersions();
    expect(versions.accept({'orderId': 'o', 'version': 3}), true);
    expect(versions.accept({'orderId': 'o', 'version': 3}), false);
    expect(versions.accept({'orderId': 'o', 'version': 2}), false);
    expect(versions.accept({'orderId': 'o', 'version': 4}), true);
  });
  testWidgets('owner action waits for server and blocks repeated taps', (
    tester,
  ) async {
    final repo = OperationRepo()..pendingAction = Completer<dynamic>();
    var refreshed = 0;
    await tester.pumpWidget(
      ProviderScope(
        overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
        child: MaterialApp(
          home: Scaffold(
            body: OperationCard(
              order: repo.current,
              scope: 'restaurant',
              onChanged: () => refreshed++,
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Accept'));
    await tester.pump();
    await tester.tap(find.text('Accept'));
    await tester.pump();
    expect(repo.writes, 1);
    expect(refreshed, 0);
    expect(find.text('Accepted'), findsNothing);
    repo.pendingAction!.complete({'status': 'ACCEPTED'});
    await tester.pumpAndSettle();
    expect(refreshed, 1);
  });
  testWidgets(
    'backend eligibility hides acceptance and explains unpaid order',
    (tester) async {
      final o = order()
        ..['availableActions'] = ['reject']
        ..['paymentEligible'] = false;
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: OperationCard(
                order: o,
                scope: 'restaurant',
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      expect(find.text('Accept'), findsNothing);
      expect(find.textContaining('not eligible'), findsOneWidget);
    },
  );
  testWidgets('live event and reconnect refresh authoritative REST snapshot', (
    tester,
  ) async {
    final updates = StreamController<LiveOrderUpdate>.broadcast();
    final account = FakeAuth()..saved = session();
    addTearDown(account.events.close);
    final repo = OperationRepo();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commerceRepositoryProvider.overrideWithValue(repo),
          liveOrdersProvider.overrideWith((ref) => updates.stream),
          authRepositoryProvider.overrideWithValue(account),
        ],
        child: const MaterialApp(
          home: OperationsScreen(scope: 'restaurant', orderId: 'o'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final reads = repo.reads;
    repo.current = {
      ...repo.current,
      'status': 'PREPARING',
      'availableActions': ['ready'],
    };
    updates.add(const LiveOrderUpdate('Live updates connected', orderId: 'o'));
    await tester.pumpAndSettle();
    expect(repo.reads, greaterThan(reads));
    expect(find.text('Preparing'), findsOneWidget);
    repo.current = {
      ...repo.current,
      'status': 'READY_FOR_PICKUP',
      'availableActions': [],
    };
    updates.add(
      const LiveOrderUpdate('Live updates connected', reconcile: true),
    );
    await tester.pumpAndSettle();
    expect(find.text('Ready for pickup'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    unawaited(updates.close());
  });
}
