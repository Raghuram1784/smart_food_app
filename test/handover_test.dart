import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/customer_handover_card.dart';
import 'package:smart_food_demo/features/commerce/operations_screen.dart';

import 'commerce_test.dart' show FakeCommerce;

class HandoverFakeRepo extends FakeCommerce {
  Json? handoverData;
  Json orderData = {
    'id': 'order-1',
    'orderNumber': 'FD-HANDOVER-1',
    'restaurantName': 'Bawarchi Express',
    'createdAt': '2026-11-13T12:00:00Z',
    'version': 3,
    'status': 'OUT_FOR_DELIVERY',
    'paymentStatus': 'PAID',
    'finalPayablePaise': 45000,
    'items': [
      {'name': 'Chicken Biryani', 'quantity': 1, 'addOns': []},
    ],
    'deliveryAddressSnapshot': {
      'recipientName': 'Rahul Varma',
      'contactNumber': '9876543210',
      'addressLine1': 'Flat 402, Skyline Towers',
      'localityName': 'Madhapur',
      'postalCode': '500081',
    },
    'availableActions': ['complete-handover'],
  };

  final requestLog = <String>[];
  Json? lastPostData;
  Object? postError;

  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    requestLog.add('$method $path');
    lastPostData = data;

    if (method == 'GET' && path == 'orders/order-1/handover') {
      return handoverData ??
          {
            'orderId': 'order-1',
            'orderVersion': 3,
            'state': 'NOT_ISSUED',
            'challengeVersion': null,
            'issuedAt': null,
            'expiresAt': null,
            'nextIssueAt': null,
            'attemptsRemaining': 5,
            'issuesRemaining': 5,
            'canIssue': true,
            'consumedAt': null,
          };
    }

    if (method == 'POST' && path == 'orders/order-1/handover/issue') {
      if (postError != null) throw postError!;
      handoverData = {
        'orderId': 'order-1',
        'orderVersion': 3,
        'state': 'ACTIVE',
        'challengeVersion': 1,
        'issuedAt': DateTime.now().toIso8601String(),
        'expiresAt': DateTime.now()
            .add(const Duration(minutes: 10))
            .toIso8601String(),
        'nextIssueAt': DateTime.now()
            .add(const Duration(seconds: 30))
            .toIso8601String(),
        'attemptsRemaining': 5,
        'issuesRemaining': 4,
        'canIssue': true,
        'pin': '042819',
        'consumedAt': null,
      };
      return handoverData;
    }

    if (method == 'POST' &&
        path == 'operations/delivery/orders/order-1/complete-handover') {
      if (postError != null) throw postError!;
      orderData['status'] = 'DELIVERED';
      orderData['version'] = 4;
      return {
        ...orderData,
        'handoverVerified': true,
        'alreadyCompleted': false,
      };
    }

    return super.request(method, path, data);
  }
}

void main() {
  group('CustomerHandoverCard', () {
    testWidgets('hidden when order is not out for delivery', (tester) async {
      final repo = HandoverFakeRepo();
      final order = {...repo.orderData, 'status': 'PREPARING'};

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(body: CustomerHandoverCard(order: order)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure delivery handover'), findsNothing);
      expect(repo.requestLog, isEmpty);
    });

    testWidgets('shows generate button when NOT_ISSUED and issues PIN on tap', (
      tester,
    ) async {
      final repo = HandoverFakeRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(body: CustomerHandoverCard(order: repo.orderData)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Secure delivery handover'), findsOneWidget);
      expect(find.text('Request delivery OTP'), findsOneWidget);
      expect(repo.requestLog, contains('GET orders/order-1/handover'));

      // Tap generate PIN
      await tester.tap(find.text('Request delivery OTP'));
      await tester.pumpAndSettle();

      expect(repo.requestLog, contains('POST orders/order-1/handover/issue'));
      expect(find.text('042819'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('5 attempts left'), findsOneWidget);
      expect(
        find.textContaining('Do not share this PIN over phone or message'),
        findsOneWidget,
      );
    });

    testWidgets('displays active PIN, timer and regenerate button', (
      tester,
    ) async {
      final repo = HandoverFakeRepo()
        ..handoverData = {
          'orderId': 'order-1',
          'orderVersion': 3,
          'state': 'ACTIVE',
          'challengeVersion': 1,
          'issuedAt': DateTime.now().toIso8601String(),
          'expiresAt': DateTime.now()
              .add(const Duration(minutes: 5))
              .toIso8601String(),
          'nextIssueAt': DateTime.now()
              .add(const Duration(seconds: 15))
              .toIso8601String(),
          'attemptsRemaining': 4,
          'issuesRemaining': 3,
          'canIssue': true,
          'pin': '739105',
          'consumedAt': null,
        };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(body: CustomerHandoverCard(order: repo.orderData)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('739105'), findsOneWidget);
      expect(find.text('Active'), findsOneWidget);
      expect(find.textContaining('4 attempts left'), findsOneWidget);
      expect(
        find.textContaining('Regenerate PIN (3 remaining)'),
        findsOneWidget,
      );
    });

    testWidgets('displays expired state and request new PIN button', (
      tester,
    ) async {
      final repo = HandoverFakeRepo()
        ..handoverData = {
          'orderId': 'order-1',
          'orderVersion': 3,
          'state': 'EXPIRED',
          'challengeVersion': 1,
          'issuedAt': null,
          'expiresAt': null,
          'nextIssueAt': null,
          'attemptsRemaining': 0,
          'issuesRemaining': 2,
          'canIssue': true,
          'consumedAt': null,
        };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(body: CustomerHandoverCard(order: repo.orderData)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Expired'), findsOneWidget);
      expect(find.text('Request new delivery PIN'), findsOneWidget);
    });

    testWidgets('displays locked state after 5 incorrect attempts', (
      tester,
    ) async {
      final repo = HandoverFakeRepo()
        ..handoverData = {
          'orderId': 'order-1',
          'orderVersion': 3,
          'state': 'LOCKED',
          'challengeVersion': 1,
          'issuedAt': null,
          'expiresAt': null,
          'nextIssueAt': null,
          'attemptsRemaining': 0,
          'issuesRemaining': 2,
          'canIssue': false,
          'consumedAt': null,
        };

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(body: CustomerHandoverCard(order: repo.orderData)),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Locked'), findsOneWidget);
      expect(
        find.textContaining(
          'Handover was locked after 5 incorrect PIN entries',
        ),
        findsOneWidget,
      );
    });

    testWidgets(
      'displays handover verified banner and hides PIN when delivered',
      (tester) async {
        final repo = HandoverFakeRepo();
        final deliveredOrder = {...repo.orderData, 'status': 'DELIVERED'};

        await tester.pumpWidget(
          ProviderScope(
            overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
            child: MaterialApp(
              home: Scaffold(body: CustomerHandoverCard(order: deliveredOrder)),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Handover verified'), findsOneWidget);
        expect(
          find.text('Order safely delivered with 6-digit PIN verification.'),
          findsOneWidget,
        );
        expect(find.text('042819'), findsNothing);
        expect(find.text('Request delivery OTP'), findsNothing);
      },
    );
  });

  group('Rider Handover Verification Dialog', () {
    testWidgets('opens PIN dialog and submits 6-digit PIN with leading zero', (
      tester,
    ) async {
      final repo = HandoverFakeRepo();
      var refreshed = 0;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: OperationCard(
                order: repo.orderData,
                scope: 'delivery',
                onChanged: () => refreshed++,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Confirm delivery (PIN)'), findsOneWidget);
      await tester.tap(find.text('Confirm delivery (PIN)'));
      await tester.pumpAndSettle();

      expect(find.text('Verify delivery PIN'), findsOneWidget);
      expect(find.text('FD-HANDOVER-1 · Rahul Varma'), findsOneWidget);

      // Button is initially disabled
      final confirmButtonFinder = find.widgetWithText(
        FilledButton,
        'Confirm delivery',
      );
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNull,
      );

      // Enter 4 digits -> still disabled
      await tester.enterText(find.byType(TextField), '0123');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNull,
      );

      // Enter 6 digits with leading zero
      await tester.enterText(find.byType(TextField), '042819');
      await tester.pumpAndSettle();
      expect(
        tester.widget<FilledButton>(confirmButtonFinder).onPressed,
        isNotNull,
      );

      // Tap confirm delivery
      await tester.tap(confirmButtonFinder);
      await tester.pumpAndSettle();

      expect(
        repo.requestLog,
        contains('POST operations/delivery/orders/order-1/complete-handover'),
      );
      expect(repo.lastPostData, {'pin': '042819', 'expectedVersion': 3});
      expect(refreshed, 1);
      // Dialog should have closed
      expect(find.text('Verify delivery PIN'), findsNothing);
    });

    testWidgets('shows error feedback on wrong PIN attempt', (tester) async {
      final repo = HandoverFakeRepo();

      await tester.pumpWidget(
        ProviderScope(
          overrides: [commerceRepositoryProvider.overrideWithValue(repo)],
          child: MaterialApp(
            home: Scaffold(
              body: OperationCard(
                order: repo.orderData,
                scope: 'delivery',
                onChanged: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Confirm delivery (PIN)'));
      await tester.pumpAndSettle();

      // Enter incorrect PIN
      await tester.enterText(find.byType(TextField), '999999');
      await tester.pumpAndSettle();

      // Mock an error on submission
      repo.postError = Exception('Handover PIN is incorrect');

      await tester.tap(find.widgetWithText(FilledButton, 'Confirm delivery'));
      await tester.pumpAndSettle();

      expect(
        find.textContaining('Could not complete this request'),
        findsOneWidget,
      );
      // Dialog remains open for retry
      expect(find.text('Verify delivery PIN'), findsOneWidget);
    });
  });
}
