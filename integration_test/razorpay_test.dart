import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';

// Interactive genuine TEST Checkout. Never supplies a fabricated success callback.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('genuine Razorpay test checkout and server capture', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
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
    await container.read(authProvider.future);
    await container
        .read(authProvider.notifier)
        .login(
          'customer@demo.test',
          const String.fromEnvironment('DEMO_CUSTOMER_PASSWORD'),
        );
    const id = String.fromEnvironment('EVIDENCE_ORDER_ID');
    GoRouter.of(tester.element(find.byType(Scaffold).first)).go('/orders/$id');
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Pay with Razorpay TEST').evaluate().isNotEmpty) break;
    }
    await tester.ensureVisible(find.text('Pay with Razorpay TEST'));
    await tester.tap(find.text('Pay with Razorpay TEST'));
    await tester.pump();
    var captured = false;
    await tester.runAsync(() async {
      // Native provider UI is completed interactively while this test polls the backend.
      for (var i = 0; i < 120; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        final result = await container
            .read(commerceRepositoryProvider)
            .request('GET', 'payments/orders/$id/status');
        if (result['paymentStatus'] == 'PAID') {
          captured = true;
          break;
        }
      }
    });
    expect(
      captured,
      isTrue,
      reason: 'Genuine provider capture must be confirmed by backend',
    );
    await tester.pumpAndSettle();
    await container.read(authProvider.notifier).logout();
    await tester.pumpWidget(const SizedBox());
  }, timeout: const Timeout(Duration(minutes: 10)));
}
