import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/finder/finder_controller.dart';
import 'package:smart_food_demo/features/finder/finder_models.dart';
import 'package:smart_food_demo/features/finder/finder_screen.dart';
import 'package:smart_food_demo/features/location/delivery_destination.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'finder_test.dart' show FinderFake;

/// Same route layout as the app: Home and Cart inside the bottom-nav shell,
/// the finder as a full-screen route above it.
void main() {
  testWidgets('View cart from the finder toast opens Cart and keeps the conversation', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final repo = FinderFake()..quoteTotal = 15000;
    final router = GoRouter(initialLocation: '/', routes: [
      ShellRoute(
        builder: (_, _, child) => Scaffold(body: child, bottomNavigationBar: const SizedBox(height: 40, child: Text('NAV'))),
        routes: [
          GoRoute(path: '/', builder: (_, _) => const Text('Home screen')),
          GoRoute(path: '/cart', builder: (_, _) => const Text('Cart screen')),
        ],
      ),
      GoRoute(path: '/finder', builder: (_, _) => const FinderScreen()),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
        commerceRepositoryProvider.overrideWithValue(repo),
        deliveryServiceAreaProvider.overrideWithValue(const ServiceArea('gachibowli', 'Gachibowli', 'Hyderabad')),
      ],
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    router.push('/finder');
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const ValueKey('finder-input')), 'biryani');
    await tester.tap(find.byKey(const ValueKey('finder-send')));
    await tester.pumpAndSettle();
    final add = find.descendant(of: find.byKey(const ValueKey('finder-add-1')), matching: find.byKey(const ValueKey('add-to-cart')));
    await tester.ensureVisible(add);
    await tester.pumpAndSettle();
    await tester.tap(add);
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('cart-added-toast')), matching: find.text('View cart')));
    await tester.pumpAndSettle();
    expect(find.text('Cart screen'), findsOneWidget);
    final container = ProviderScope.containerOf(tester.element(find.text('Cart screen')));
    expect(container.read(finderControllerProvider).messages.whereType<AssistantFinderMessage>(), isNotEmpty, reason: 'conversation kept');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
