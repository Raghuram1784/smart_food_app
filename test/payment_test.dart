import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/payment_panel.dart';

import 'commerce_test.dart' show FakeCommerce;

class PaymentRepo extends FakeCommerce {
  String state = 'PAYMENT_PENDING';
  int verifies = 0, creates = 0;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.endsWith('/status')) return {'paymentStatus': state};
    if (path.endsWith('/verify')) {
      verifies++;
      return {'paymentStatus': state};
    }
    if (path.endsWith('/create-order')) {
      creates++;
      return {
        'attemptId': 'attempt',
        'keyId': 'rzp_test_fixture',
        'providerOrderId': 'order_fixture',
        'amount': 36400,
        'currency': 'INR',
      };
    }
    return super.request(method, path, data);
  }
}

void main() {
  const channel = MethodChannel('razorpay_flutter');
  Future<void> mount(WidgetTester tester, PaymentRepo repo) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          commerceRepositoryProvider.overrideWithValue(repo),
          customerIdProvider.overrideWithValue('customer'),
        ],
        child: const MaterialApp(
          home: Scaffold(body: PaymentPanel(orderId: 'order')),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'SDK success stays pending until backend capture; uses server amount',
    (tester) async {
      final repo = PaymentRepo();
      Json? options;
      final result = Completer<Json>();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
        call,
      ) async {
        if (call.method == 'open') {
          options = Json.from(call.arguments);
          return result.future;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          channel,
          null,
        ),
      );
      await mount(tester, repo);
      await tester.tap(find.text('Pay with Razorpay TEST'));
      await tester.pumpAndSettle();
      expect(options?['amount'], 36400);
      expect(options?['order_id'], 'order_fixture');
      result.complete({
        'type': 0,
        'data': {
          'razorpay_payment_id': 'pay_fixture',
          'razorpay_order_id': 'order_fixture',
          'razorpay_signature': 'signature',
        },
      });
      await tester.pumpAndSettle();
      expect(repo.verifies, 1);
      expect(find.textContaining('Test payment confirmed'), findsNothing);
      repo.state = 'PAID';
      await tester.tap(find.text('Check payment status'));
      await tester.pumpAndSettle();
      expect(find.textContaining('Test payment confirmed'), findsOneWidget);
      expect(find.text('Pay with Razorpay TEST'), findsNothing);
    },
  );
  testWidgets('cancellation permits retry without claiming payment success', (
    tester,
  ) async {
    final repo = PaymentRepo();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      channel,
      (call) async => call.method == 'open'
          ? {
              'type': 1,
              'data': {'code': 2, 'message': 'Cancelled'},
            }
          : null,
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    await mount(tester, repo);
    await tester.tap(find.text('Pay with Razorpay TEST'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Checkout closed'), findsOneWidget);
    expect(repo.verifies, 0);
    await tester.tap(find.text('Pay with Razorpay TEST'));
    await tester.pumpAndSettle();
    expect(repo.creates, 2);
    expect(find.textContaining('Test payment confirmed'), findsNothing);
  });
  testWidgets('authorization blocks paying again', (tester) async {
    await mount(tester, PaymentRepo()..state = 'PAYMENT_AUTHORIZED');
    expect(find.text('Pay with Razorpay TEST'), findsNothing);
    expect(find.textContaining('Waiting for capture'), findsOneWidget);
  });
}
