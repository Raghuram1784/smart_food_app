import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/restaurant/restaurant_screen.dart';
import 'package:smart_food_demo/shared/components.dart';

import 'auth_test.dart' show FakeAuth;
import 'commerce_test.dart' show FakeCommerce;

void main() {
  testWidgets('NutritionPanel: "Nutrition unavailable" when missing (never 0); labelled estimate with serving otherwise', (tester) async {
    await tester.pumpWidget(MaterialApp(theme: appTheme(Brightness.light), home: const Scaffold(body: NutritionPanel(null))));
    expect(find.text('Nutrition unavailable'), findsOneWidget);
    expect(find.textContaining('0 kcal'), findsNothing);

    const n = Nutrition(servingDescription: '2 idlis with sambar', servingGrams: 250, caloriesKcal: 220, proteinG: 8, carbsG: 40, fatG: 3, basis: 'ESTIMATE', source: 'Estimate for a typical recipe');
    await tester.pumpWidget(MaterialApp(theme: appTheme(Brightness.light), home: const Scaffold(body: NutritionPanel(n))));
    expect(find.text('Estimate'), findsOneWidget);
    expect(find.text('220 kcal'), findsOneWidget);
    expect(find.text('8 g'), findsOneWidget);
    expect(find.text('40 g'), findsOneWidget);
    expect(find.textContaining('Per 2 idlis with sambar (~250 g)'), findsOneWidget);
    expect(find.textContaining('excludes variants and add-ons'), findsOneWidget);
    expect(find.textContaining('not lab-tested'), findsOneWidget);
    expect(Nutrition.fromJson(null), isNull);
    expect(Nutrition.fromJson({'caloriesKcal': null}), isNull);
  });

  testWidgets('restaurant menu: Veg / Non-Veg / Both filters the actual items and keeps the cart untouched', (tester) async {
    tester.view.physicalSize = const Size(393, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    const r = Restaurant('k1', 'Test Kitchen', 'Indian', 'desc', 'biryani', '30 min', 4.5);
    final menu = RestaurantMenu(r, const [
      Dish('veg-1', 'k1', 'Veg Dum Biryani', 'rice, vegetables', 'Biryani', 'biryani', 220, 'Biryanis', isVegetarian: true),
      Dish('non-1', 'k1', 'Chicken Dum Biryani', 'rice, chicken', 'Biryani', 'chicken-biryani', 320, 'Biryanis', isVegetarian: false),
    ]);
    final repo = FakeCommerce();
    final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const RestaurantScreen(id: 'k1'))]);
    addTearDown(router.dispose);
    await tester.pumpWidget(ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        authRepositoryProvider.overrideWithValue(FakeAuth()),
        commerceRepositoryProvider.overrideWithValue(repo),
        restaurantMenuProvider('k1').overrideWith((ref) async => menu),
      ],
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Veg Dum Biryani'), findsOneWidget);
    expect(find.text('Chicken Dum Biryani'), findsOneWidget);
    await tester.tap(find.text('Veg'));
    await tester.pumpAndSettle();
    expect(find.text('Veg Dum Biryani'), findsOneWidget);
    expect(find.text('Chicken Dum Biryani'), findsNothing);
    await tester.tap(find.text('Non-Veg'));
    await tester.pumpAndSettle();
    expect(find.text('Veg Dum Biryani'), findsNothing);
    expect(find.text('Chicken Dum Biryani'), findsOneWidget);
    await tester.tap(find.text('Both'));
    await tester.pumpAndSettle();
    expect(find.text('Veg Dum Biryani'), findsOneWidget);
    expect(find.text('Chicken Dum Biryani'), findsOneWidget);
    expect(repo.calls.where((c) => c.startsWith('DELETE') || c.startsWith('PATCH')), isEmpty, reason: 'filter never changes the cart');
    expect(tester.takeException(), isNull);
  });
}
