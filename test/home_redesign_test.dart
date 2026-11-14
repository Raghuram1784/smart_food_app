import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:dio/dio.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart' as local;
import 'package:smart_food_demo/features/catalog/catalog.dart' show Dish;
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/catalog/diet_preference.dart';
import 'package:smart_food_demo/features/discovery/home_screen.dart';

import 'auth_test.dart' show FakeAuth;

/// Offline fixture + explicit server-style veg classification, filtered the way
/// the API does (diet=veg|nonveg on MenuItem.isVegetarian).
class DietCatalog extends OfflineCatalogRepository {
  static final _veg = {'dosa', 'idli', 'paneer', 'pasta', 'salad', 'pizza-margherita'};
  @override
  Future<HomeCatalog> home(String? area, CancelToken token, {String? diet}) async {
    final base = await super.home(area, token);
    final dishes = [
      for (final d in base.dishes)
        Dish(d.id, d.restaurantId, d.name, d.description, d.category, d.image, d.price, d.section,
            restaurantName: d.restaurantName, isVegetarian: _veg.contains(d.id) || _veg.contains(d.image)),
    ].where((d) => diet == null || d.isVegetarian == (diet == 'veg')).toList();
    return HomeCatalog(base.restaurants, dishes, base.categories);
  }
}

Future<void> _mount(WidgetTester tester, {bool reduceMotion = false}) async {
  tester.view.physicalSize = const Size(393, 1800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  Widget page(String t) => Scaffold(body: Text(t));
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const Scaffold(body: HomeScreen())),
    GoRoute(path: '/restaurants', builder: (_, _) => const AllRestaurantsScreen()),
    GoRoute(path: '/search', builder: (_, s) => page('Search ${s.uri.query}')),
    GoRoute(path: '/restaurant/:id', builder: (_, s) => page('Restaurant ${s.pathParameters['id']}')),
    GoRoute(path: '/account', builder: (_, _) => page('Account')),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()),
      catalogRepositoryProvider.overrideWithValue(DietCatalog()),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: const Size(393, 1800), disableAnimations: reduceMotion),
      child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router),
    ),
  ));
  await tester.pumpAndSettle();
}

int _page(WidgetTester tester) =>
    tester.widget<PageView>(find.byKey(const ValueKey('promo-carousel'))).controller!.page!.round();

void main() {
  testWidgets('slideshow auto-advances, swipes, links to real catalog routes, and cleans up its timer', (tester) async {
    await _mount(tester);
    expect(find.byKey(const ValueKey('promo-carousel')), findsOneWidget);
    expect(_page(tester), 0);
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
    expect(_page(tester), 1, reason: 'auto-advance after 5 s');
    await tester.drag(find.byKey(const ValueKey('promo-carousel')), const Offset(-300, 0));
    await tester.pumpAndSettle();
    expect(_page(tester), 2, reason: 'manual swipe');
    // Tapping a slide opens a real route (category search or restaurant menu).
    await tester.tap(find.byKey(const ValueKey('promo-carousel')));
    await tester.pumpAndSettle();
    expect(find.textContaining(RegExp(r'^(Search category=|Restaurant )')), findsOneWidget);
    await tester.pumpWidget(const SizedBox()); // timers must be gone (framework verifies)
  });

  testWidgets('reduced motion: no automatic transitions', (tester) async {
    await _mount(tester, reduceMotion: true);
    await tester.pump(const Duration(seconds: 12));
    await tester.pumpAndSettle();
    expect(_page(tester), 0);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Browse restaurants shows every catalog restaurant; View all lists them; no outdated copy', (tester) async {
    await _mount(tester);
    final count = local.restaurants.length;
    expect(find.text('Browse restaurants'), findsOneWidget);
    expect(find.text('$count kitchens'), findsOneWidget);
    expect(find.textContaining('Ordering is not yet available'), findsNothing);
    await tester.tap(find.text('View all'));
    await tester.pumpAndSettle();
    expect(find.text('All restaurants'), findsOneWidget);
    for (final r in local.restaurants) {
      await tester.scrollUntilVisible(find.text(r.name).last, 300, scrollable: find.byType(Scrollable).last);
      expect(find.text(r.name), findsWidgets);
    }
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('Veg / Non-Veg / Both changes the dishes shown (Both is default)', (tester) async {
    await _mount(tester);
    final container = ProviderScope.containerOf(tester.element(find.byType(HomeScreen)));
    expect(container.read(dietPreferenceProvider), DietPreference.both);
    bool any(bool veg) => tester.widgetList<VegMark>(find.byType(VegMark)).any((m) => m.veg == veg && m.size == 14 && find.byWidget(m).evaluate().isNotEmpty);
    await tester.tap(find.text('Veg').first);
    await tester.pumpAndSettle();
    expect(container.read(dietPreferenceProvider), DietPreference.veg);
    final cards = tester.widgetList<DishCard>(find.byType(DishCard));
    expect(cards, isNotEmpty);
    expect(cards.every((c) => c.dish.isVegetarian == true), isTrue);
    await tester.tap(find.text('Non-Veg').first);
    await tester.pumpAndSettle();
    final nonVeg = tester.widgetList<DishCard>(find.byType(DishCard));
    expect(nonVeg.every((c) => c.dish.isVegetarian == false), isTrue);
    await tester.tap(find.text('Both').first);
    await tester.pumpAndSettle();
    expect(any(true) || any(false), isTrue);
    await tester.pumpWidget(const SizedBox());
  });
}
