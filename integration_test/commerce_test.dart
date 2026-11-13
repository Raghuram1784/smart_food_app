import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('real customer checkout to owner inbox', (tester) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('appearance', 'light');
    await prefs.setString('locality', 'madhapur');
    await SecureTokenStorage().delete();
    Future<void> launch() async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [preferencesProvider.overrideWithValue(prefs)],
          child: const FoodApp(),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> waitFor(Finder finder) async {
      for (var i = 0; i < 200; i++) {
        await tester.pump(const Duration(milliseconds: 100));
        if (finder.evaluate().isNotEmpty) {
          await tester.pumpAndSettle();
          return;
        }
      }
      expect(finder, findsWidgets);
    }

    Future<void> tap(Finder finder) async {
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          250,
          scrollable: find.byType(Scrollable).last,
        );
      }
      await tester.ensureVisible(finder);
      await tester.pumpAndSettle();
      if (finder.hitTestable().evaluate().isEmpty) {
        await tester.drag(find.byType(Scrollable).last, const Offset(0, -250));
        await tester.pumpAndSettle();
      }
      await tester.tap(finder);
      await tester.pumpAndSettle();
    }

    ProviderContainer scope() =>
        ProviderScope.containerOf(tester.element(find.byType(FoodApp)));
    GoRouter router() =>
        GoRouter.of(tester.element(find.byType(Scaffold).first));
    Future<void> login(String email, String password) async {
      router().go('/login');
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('login-email')), email);
      await tester.enterText(
        find.byKey(const ValueKey('login-password')),
        password,
      );
      FocusManager.instance.primaryFocus?.unfocus();
      await tap(find.text('Sign in'));
      await waitFor(find.text(email));
    }

    final public = Dio(
      BaseOptions(baseUrl: const String.fromEnvironment('API_BASE_URL')),
    );
    final menu = (await public.get('restaurants/deccan-handi-gachi/menu'))
        .data['data'];
    final items = (menu['sections'] as List)
        .expand((section) => section['items'] as List)
        .toList();
    final first = items.firstWhere(
      (i) =>
          i['availabilityStatus'] == 'AVAILABLE' &&
          (i['variants'] as List).any((v) => v['isAvailable'] == true) &&
          (i['addOns'] as List).any((a) => a['isAvailable'] == true),
    );
    final second = items.firstWhere(
      (i) => i['id'] != first['id'] && i['availabilityStatus'] == 'AVAILABLE',
    );
    await launch();
    await binding.convertFlutterSurfaceToImage();
    await login(
      'customer@demo.test',
      const String.fromEnvironment('DEMO_CUSTOMER_PASSWORD'),
    );
    final repo = scope().read(commerceRepositoryProvider);
    final original = await repo.request('GET', 'cart');
    if ((original['items'] as List).isNotEmpty) {
      expect(
        (original['items'] as List).every(
          (l) => [first['id'], second['id']].contains(l['menuItemId']),
        ),
        true,
        reason: 'Do not clear unrelated user selections',
      );
      await repo.request('DELETE', 'cart', {
        'expectedVersion': original['version'],
      });
    }
    router().go('/restaurant/deccan-handi-gachi');
    await tester.pumpAndSettle();
    await waitFor(find.text(menu['restaurant']['name']).first);
    await tap(find.text(first['name']).first);
    await waitFor(find.text('Customize meal'));
    final variant = (first['variants'] as List).firstWhere(
      (v) => v['isAvailable'] == true,
    );
    final addon = (first['addOns'] as List).firstWhere(
      (a) => a['isAvailable'] == true,
    );
    await tap(
      find.widgetWithText(
        ChoiceChip,
        '${variant['name']} · +₹${(variant['priceAdjustmentPaise'] as int) ~/ 100}',
      ),
    );
    await tap(
      find.widgetWithText(
        FilterChip,
        '${addon['name']} · +₹${(addon['pricePaise'] as int) ~/ 100}',
      ),
    );
    await tap(find.text('Add to cart'));
    await waitFor(find.text('Added to your cart'));
    Navigator.of(tester.element(find.text('Customize meal'))).pop();
    await tester.pumpAndSettle();
    await tap(find.text(second['name']).first);
    await waitFor(find.text('Customize meal'));
    await tap(find.text('Add to cart'));
    await waitFor(find.text('Added to your cart'));
    Navigator.of(tester.element(find.text('Customize meal'))).pop();
    await tester.pumpAndSettle();
    // Recreate the complete app state; only the server retains the cart.
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    await launch();
    router().go('/cart');
    await waitFor(find.text(first['name']));
    await tap(find.byTooltip('Increase ${first['name']}'));
    await waitFor(find.text('Bill summary'));
    await tester.drag(find.byType(Scrollable).last, const Offset(0, 400));
    await tester.pumpAndSettle();
    final cart = await scope()
        .read(commerceRepositoryProvider)
        .request('GET', 'cart');
    expect(cart['items'].length, 2);
    expect(
      (cart['items'] as List).firstWhere(
        (l) => l['menuItemId'] == first['id'],
      )['quantity'],
      2,
    );
    await binding.takeScreenshot('01-cart-multiple-items-light');
    if (find.textContaining('Synthetic demo home').evaluate().isEmpty) {
      if (find.text('Manage delivery addresses').evaluate().isNotEmpty) {
        await tap(find.text('Manage delivery addresses'));
      } else {
        await tap(find.text('Choose delivery address').first);
      }
      await tap(find.text('Add address').last);
      for (final field in {
        'label': 'Synthetic demo home',
        'recipientName': 'Demo Customer',
        'contactNumber': '9999999999',
        'addressLine1': '100 Synthetic Demo Lane',
        'postalCode': '500081',
      }.entries) {
        final finder = find.byKey(ValueKey('address-${field.key}'));
        await tester.ensureVisible(finder);
        await tester.enterText(finder, field.value);
      }
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Save address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Save address'));
      await waitFor(find.textContaining('Synthetic demo home'));
      router().go('/cart');
      await tester.pumpAndSettle();
      await waitFor(find.text('Review order'));
    }
    await tester.drag(find.byType(Scrollable).last, const Offset(0, -450));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('02-cart-selected-address-light');
    await scope().read(appearanceProvider.notifier).select(ThemeMode.dark);
    await tester.pumpAndSettle();
    await binding.takeScreenshot('09-cart-dark');
    await scope().read(appearanceProvider.notifier).select(ThemeMode.light);
    await tester.pumpAndSettle();
    await tap(find.text('Review order'));
    await waitFor(find.text('Confirm order'));
    await binding.takeScreenshot('03-checkout-light');
    await tap(find.text('Confirm order'));
    await waitFor(find.text('Your order has been recorded'));
    final orderId =
        router().routeInformationProvider.value.uri.pathSegments.last;
    final order = await scope()
        .read(commerceRepositoryProvider)
        .request('GET', 'orders/$orderId');
    expect(order['status'], 'PENDING_RESTAURANT');
    expect(order['paymentStatus'], 'UNPAID');
    expect(order['items'].length, 2);
    expect(order['events'].length, 1);
    expect(order['deliveryPaise'], 2000);
    expect(order['platformPaise'], 500);
    expect(order['packagingPaise'], 1000);
    final lineSum = (order['items'] as List).fold<int>(
      0,
      (n, l) => n + (l['lineTotalPaise'] as int),
    );
    expect(order['finalPayablePaise'], lineSum + 3500);
    await binding.takeScreenshot('04-order-confirmation-light');
    await tap(find.text('View order details'));
    await waitFor(find.text('Ordered items'));
    await waitFor(find.text(order['orderNumber']));
    await binding.takeScreenshot('06-customer-order-details-light');
    await tap(find.text('View order history'));
    await waitFor(find.text('Your orders'));
    await binding.takeScreenshot('05-customer-order-history-light');
    await scope().read(authProvider.notifier).logout();
    await login(
      'restaurant@demo.test',
      const String.fromEnvironment('DEMO_RESTAURANT_PASSWORD'),
    );
    await scope().read(appearanceProvider.notifier).select(ThemeMode.dark);
    await tester.pumpAndSettle();
    await tap(find.text('${menu['restaurant']['name']} · Incoming orders'));
    await waitFor(find.textContaining('pending'));
    await binding.takeScreenshot('07-owner-inbox-dark');
    await tap(find.text('View details').first);
    await waitFor(find.text('Ordered items'));
    await binding.takeScreenshot('08-owner-order-detail-dark');
    final ownerRepo = scope().read(commerceRepositoryProvider);
    try {
      await ownerRepo.request('GET', 'restaurants/other-kitchen/orders');
      fail('Unrelated restaurant access should fail');
    } on DioException catch (e) {
      expect(e.response?.statusCode, 403);
    }
    final search = await public.get(
      'catalog/smart-search',
      queryParameters: {'area': 'madhapur', 'q': 'dosa'},
    );
    expect(search.statusCode, 200);
    final quote = await public.post(
      'pricing/quote',
      data: {
        'restaurantId': 'deccan-handi-gachi',
        'menuItemId': first['id'],
        'area': 'madhapur',
        'quantity': 1,
        'addOnIds': [],
      },
    );
    expect(quote.statusCode, 200);
    binding.reportData = {
      ...?binding.reportData,
      'orderId': orderId,
      'orderNumber': order['orderNumber'],
      'finalPayablePaise': order['finalPayablePaise'],
      'status': order['status'],
      'paymentStatus': order['paymentStatus'],
    };
    await scope().read(authProvider.notifier).logout();
    public.close();
    await tester.pumpWidget(const SizedBox());
  });
}
