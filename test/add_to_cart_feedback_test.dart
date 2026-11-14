import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_widgets.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce;

class SlowCartCommerce extends FakeCommerce {
  int posts = 0;
  Object? postFailure;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path == 'cart/items' && method == 'POST') {
      posts++;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      if (postFailure != null) throw postFailure!;
    }
    return super.request(method, path, data);
  }
}

Future<GoRouter> _mount(WidgetTester tester, SlowCartCommerce repo) async {
  tester.view.physicalSize = const Size(393, 852);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(routes: [
    GoRoute(
      path: '/',
      builder: (context, _) => Scaffold(
        bottomNavigationBar: const ViewCartBar(),
        body: Center(
          child: Builder(
            builder: (context) => FilledButton(
              onPressed: () => showModalBottomSheet<void>(
                context: context,
                useRootNavigator: true,
                builder: (_) => const Padding(
                  padding: EdgeInsets.all(20),
                  child: AddToCartButton(
                    itemName: 'Masala Dosa',
                    selection: {'restaurantId': 'kitchen', 'menuItemId': 'dosa', 'quantity': 2, 'addOnIds': <String>[]},
                  ),
                ),
              ),
              child: const Text('Open dish'),
            ),
          ),
        ),
      ),
    ),
    GoRoute(path: '/cart', builder: (_, _) => const Scaffold(body: Text('Cart screen'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
      commerceRepositoryProvider.overrideWithValue(repo),
    ],
    child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  return router;
}

void main() {
  testWidgets('success toast only after the server confirms; visible above the dish sheet; View cart closes the sheet and opens Cart', (tester) async {
    final repo = SlowCartCommerce();
    await _mount(tester, repo);
    await tester.tap(find.text('Open dish'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-to-cart')));
    await tester.tap(find.byKey(const ValueKey('add-to-cart')), warnIfMissed: false); // rapid second tap
    await tester.pump(const Duration(milliseconds: 10));
    expect(find.byKey(const ValueKey('cart-added-toast')), findsNothing, reason: 'no success before the server responds');
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(repo.posts, 1, reason: 'duplicate taps send one request');
    expect(find.byKey(const ValueKey('cart-added-toast')), findsOneWidget);
    expect(find.text('Added 2 × Masala Dosa'), findsOneWidget);
    // Toast sits at the top, above the sheet.
    expect(tester.getRect(find.byKey(const ValueKey('cart-added-toast'))).top, lessThan(200));
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('cart-added-toast')), matching: find.text('View cart')));
    await tester.pumpAndSettle();
    expect(find.text('Cart screen'), findsOneWidget);
    expect(find.byKey(const ValueKey('add-to-cart')), findsNothing, reason: 'sheet closed');
    expect(tester.takeException(), isNull);
  });

  testWidgets('failure shows an actionable error and no success toast; toast auto-dismisses', (tester) async {
    final repo = SlowCartCommerce()
      ..postFailure = DioException(
        requestOptions: RequestOptions(),
        response: Response(requestOptions: RequestOptions(), statusCode: 422, data: {'error': {'message': 'Item is unavailable'}}),
      );
    await _mount(tester, repo);
    await tester.tap(find.text('Open dish'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('add-to-cart')));
    await tester.pumpAndSettle();
    expect(find.text('Item is unavailable'), findsOneWidget);
    expect(find.byKey(const ValueKey('cart-added-toast')), findsNothing);

    repo.postFailure = null;
    await tester.tap(find.byKey(const ValueKey('add-to-cart')));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.pump();
    expect(find.byKey(const ValueKey('cart-added-toast')), findsOneWidget);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('cart-added-toast')), findsNothing, reason: 'auto-dismissed');
  });

  testWidgets('sticky View Cart bar shows server cart count and opens Cart', (tester) async {
    final repo = SlowCartCommerce();
    await _mount(tester, repo);
    expect(find.byKey(const ValueKey('view-cart-bar')), findsOneWidget);
    expect(find.textContaining('View cart'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('view-cart-bar')));
    await tester.pumpAndSettle();
    expect(find.text('Cart screen'), findsOneWidget);
  });
}
