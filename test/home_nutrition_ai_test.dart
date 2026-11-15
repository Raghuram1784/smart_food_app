import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/finder/finder_screen.dart';
import 'package:smart_food_demo/features/location/delivery_destination.dart';
import 'package:smart_food_demo/shared/components.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'finder_test.dart' show FinderFake, rec, results;

void main() {
  testWidgets('NutritionLine: compact kcal/protein chips with provenance; unavailable is explicit, never 0', (tester) async {
    const n = Nutrition(servingDescription: '1 plate', servingGrams: 350, caloriesKcal: 600, proteinG: 30, carbsG: 70, fatG: 22, basis: 'ESTIMATE', source: 'Estimate for a typical serving');
    await tester.pumpWidget(MaterialApp(theme: appTheme(Brightness.light), home: const Scaffold(body: Column(children: [NutritionLine(n), NutritionLine(null)]))));
    expect(find.text('600 kcal'), findsOneWidget);
    expect(find.text('30 g protein'), findsOneWidget);
    expect(find.text('Calories & protein unavailable'), findsOneWidget);
    expect(find.textContaining('0 kcal'), findsOneWidget, reason: 'only the real 600 kcal');
    await tester.tap(find.byIcon(Icons.info_outline));
    await tester.pumpAndSettle();
    expect(find.textContaining('Estimated per 1 plate (~350 g)'), findsOneWidget);
  });

  testWidgets('Compact AI row and search-bar AI shortcut open the finder', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Column(children: [Padding(padding: EdgeInsets.all(16), child: FinderEntryCard())]))),
      GoRoute(path: '/finder', builder: (_, _) => const Scaffold(body: Text('Finder route'))),
    ]);
    addTearDown(router.dispose);
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 740), textScaler: TextScaler.linear(2)),
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ));
    expect(tester.takeException(), isNull, reason: 'no overflow at 360 px / 200% text');
    await tester.pumpWidget(MediaQuery(
      data: const MediaQueryData(size: Size(360, 740)),
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ));
    expect(tester.getSize(find.byKey(const ValueKey('finder-entry'))).height, lessThanOrEqualTo(110), reason: 'compact row (the old banner was over 220 px)');
    await tester.tap(find.byKey(const ValueKey('finder-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Finder route'), findsOneWidget);
  });

  testWidgets('"Add the first option" adds that dish through the cart API exactly once', (tester) async {
    tester.view.physicalSize = const Size(412, 915);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final pick = rec(id: 'mini', restaurantId: 'kitchen', total: 14400);
    final repo = FinderFake()
      ..quoteTotal = 14400
      ..replies.add((_) => results())
      ..replies.add((_) => {
            'conversationId': '11111111-1111-4111-8111-111111111111',
            'status': 'SELECTED',
            'reply': 'Adding Mini Chicken Dum Biryani from Deccan Handi & Dum to your cart.',
            'interpreter': 'gemini',
            'selected': pick,
            'requiresBudgetConfirmation': false,
          });
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const FinderScreen()),
      GoRoute(path: '/cart', builder: (_, _) => const Scaffold(body: Text('Cart screen'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
        commerceRepositoryProvider.overrideWithValue(repo),
        deliveryServiceAreaProvider.overrideWithValue(const ServiceArea('kukatpally', 'Kukatpally / KPHB', 'Hyderabad')),
      ],
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    for (final m in ['chicken biryani under ₹150', 'Add the first option']) {
      await tester.enterText(find.byKey(const ValueKey('finder-input')), m);
      await tester.tap(find.byKey(const ValueKey('finder-send')));
      await tester.pump();
      await tester.pumpAndSettle();
    }
    expect(repo.calls.where((c) => c == 'POST pricing/quote').length, 1, reason: 're-quoted before adding');
    expect(repo.calls.where((c) => c == 'POST cart/items').length, 1, reason: 'added once via the cart API');
    expect(find.byKey(const ValueKey('cart-added-toast')), findsOneWidget);
    // Scrolling away and back must not add again.
    final list = find.byType(Scrollable).first;
    await tester.drag(list, const Offset(0, 3000));
    await tester.pumpAndSettle();
    await tester.drag(list, const Offset(0, -6000));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'POST cart/items').length, 1);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });
}
