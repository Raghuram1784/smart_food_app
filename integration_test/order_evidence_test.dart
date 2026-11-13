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

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('capture existing recorded order and authorized owner inbox', (
    tester,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', 'light');
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
    await container.read(authProvider.future);
    await container
        .read(authProvider.notifier)
        .login(
          'customer@demo.test',
          const String.fromEnvironment('DEMO_CUSTOMER_PASSWORD'),
        );
    router.go(
      '/orders/${const String.fromEnvironment('EVIDENCE_ORDER_ID')}?placed=true',
    );
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Your order has been recorded').evaluate().isNotEmpty) {
        break;
      }
    }
    await tester.pumpAndSettle();
    expect(find.text('Your order has been recorded'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('04-order-confirmation-light');
    await tester.tap(find.text('View order details'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Ordered items').evaluate().isNotEmpty) break;
    }
    await binding.takeScreenshot('06-customer-order-details-light');
    await tester.tap(find.text('View order history'));
    await tester.pumpAndSettle();
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('View details').evaluate().isNotEmpty) break;
    }
    await binding.takeScreenshot('05-customer-order-history-light');
    await container.read(authProvider.notifier).logout();
    await container
        .read(authProvider.notifier)
        .login(
          'restaurant@demo.test',
          const String.fromEnvironment('DEMO_RESTAURANT_PASSWORD'),
        );
    router.go('/inbox/deccan-handi-gachi');
    await container.read(appearanceProvider.notifier).select(ThemeMode.dark);
    for (var i = 0; i < 150; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.textContaining('Open an order to manage').evaluate().isNotEmpty) break;
    }
    await tester.pumpAndSettle();
    expect(find.textContaining('Open an order to manage'), findsOneWidget);
    await binding.takeScreenshot('07-owner-inbox-dark');
    await tester.tap(find.text('View details').first);
    await tester.pumpAndSettle();
    for (var i = 0; i < 100; i++) {
      await tester.pump(const Duration(milliseconds: 100));
      if (find.text('Ordered items').evaluate().isNotEmpty) break;
    }
    await binding.takeScreenshot('08-owner-order-detail-dark');
    await container.read(authProvider.notifier).logout();
    await tester.pumpWidget(const SizedBox());
  });
}
