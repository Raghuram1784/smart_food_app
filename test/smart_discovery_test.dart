import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/discovery/meal_comparison_sheet.dart';
import 'package:smart_food_demo/features/discovery/smart_empty_state.dart';
import 'package:smart_food_demo/features/discovery/smart_filters.dart';
import 'package:smart_food_demo/features/discovery/smart_search_screen.dart';
import 'package:smart_food_demo/features/pricing/pricing_repository.dart';
import 'package:smart_food_demo/features/pricing/quote_panel.dart';

final fixture = jsonDecode(
  File('test/fixtures/smart_page.json').readAsStringSync(),
) as Map<String, dynamic>;

class TestPricing extends PricingRepository {
  TestPricing() : super(Dio());
  final searches = <SmartQuery>[];
  final quotes = <QuoteRequest>[];
  final comparisons = <CompareRequest>[];
  bool fail = false;
  int? totalOverride;
  DioException? quoteRejection;
  @override
  Future<SmartPage> search(
    SmartQuery q,
    CancelToken token, {
    int limit = 12,
  }) async {
    searches.add(q);
    if (fail) throw Exception('network unavailable');
    final empty = q.budget == 15000 || q.text == 'unknown';
    return SmartPage.fromJson({
      ...fixture,
      if (empty) 'items': [],
      if (empty)
        'total': 0
      else if (totalOverride != null)
        'total': totalOverride,
      'page': q.page,
    });
  }

  @override
  Future<MealQuote> quote(QuoteRequest q, CancelToken token) async {
    quotes.add(q);
    if (quoteRejection != null) throw quoteRejection!;
    final raw = Map<String, dynamic>.from(
      (fixture['items'] as List).last['quote'],
    );
    // Deliberately distinct server response: widget must display it, never reconstruct a total.
    raw['finalPayablePaise'] = q.addOns.isEmpty ? 17400 : 19837;
    if (q.variant != null) {
      raw['selectedVariant'] = {'id': q.variant};
    }
    raw['quoteFingerprint'] = '${q.variant}-${q.addOns}-${q.quantity}';
    return MealQuote.fromJson(raw);
  }

  @override
  Future<List<MealQuote>> compare(CompareRequest q, CancelToken token) async {
    comparisons.add(q);
    return (fixture['items'] as List)
        .take(2)
        .map((r) => MealQuote.fromJson(r['quote']))
        .toList();
  }

  @override
  Future<List<({String id, String name})>> choices(
    String path,
    CancelToken token,
  ) async => [(id: 'south-indian', name: 'South Indian')];
}

Future<void> host(
  WidgetTester tester,
  TestPricing repo,
  Widget child, {
  Brightness brightness = Brightness.light,
}) async {
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        preferencesProvider.overrideWithValue(prefs),
        catalogRepositoryProvider.overrideWithValue(OfflineCatalogRepository()),
        pricingRepositoryProvider.overrideWithValue(repo),
      ],
      child: MaterialApp(
        theme: appTheme(brightness),
        home: Scaffold(body: child),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  test('budget input preserves exact paise and rejects invalid amounts', () {
    expect(parseBudget('150'), 15000);
    expect(parseBudget('149.99'), 14999);
    expect(parseBudget('150.01'), 15001);
    expect(parseBudget('0'), 0);
    expect(parseBudget(''), isNull);
    for (final bad in ['-1', 'x', '1.001', '1e3']) {
      expect(() => parseBudget(bad), throwsFormatException);
    }
  });
  testWidgets('search debounce, vegetarian and reset reach the server query', (
    tester,
  ) async {
    final repo = TestPricing();
    await host(tester, repo, const SmartSearchScreen());
    expect(find.text('A starting point'), findsOneWidget);
    await tester.enterText(
      find.byKey(const ValueKey('smart-search-input')),
      'unknown',
    );
    await tester.pump(const Duration(milliseconds: 350));
    await tester.pumpAndSettle();
    expect(repo.searches.last.text, 'unknown');
    await tester.tap(find.text('Vegetarian'));
    await tester.pumpAndSettle();
    expect(repo.searches.last.vegetarian, true);
    await tester.tap(find.text('Reset filters'));
    await tester.pumpAndSettle();
    expect(repo.searches.last.text, '');
    expect(repo.searches.last.vegetarian, isNull);
  });
  testWidgets(
    'budget sheet applies a total-payable limit and shows honest empty state',
    (tester) async {
      final repo = TestPricing();
      await host(tester, repo, const SmartSearchScreen());
      await tester.tap(find.byTooltip('Meal filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('budget-input')), '150');
      FocusManager.instance.primaryFocus?.unfocus();
      tester.testTextInput.hide();
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show matching meals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show matching meals'));
      await tester.pumpAndSettle();
      expect(repo.searches.last.budget, 15000);
      await tester.scrollUntilVisible(
        find.text('Nothing fits just yet.'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Nothing fits just yet.'), findsOneWidget);
    },
  );
  testWidgets('customization sends IDs and renders the returned quote total', (
    tester,
  ) async {
    final repo = TestPricing();
    final dish = Dish.fromJson(
      (fixture['items'] as List).last['quote']['item'],
    );
    await host(
      tester,
      repo,
      SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: DishQuotePanel(dish),
        ),
      ),
    );
    final option = dish.addOnOptions.first;
    await tester.tap(
      find.text('${option.name} · +₹${formatPaise(option.pricePaise)}'),
    );
    await tester.pumpAndSettle();
    expect(repo.quotes.last.addOns, option.id);
    await tester.ensureVisible(find.text('₹198.37'));
    await tester.pumpAndSettle();
    expect(find.text('₹198.37'), findsOneWidget);
    await tester.ensureVisible(find.text('Reset selections'));
    await tester.tap(find.text('Reset selections'));
    await tester.pumpAndSettle();
    expect(repo.quotes.last.addOns, '');
    expect(repo.quotes.last.quantity, 1);
    // Issue B regression: variant selection updates request, rule codes show, missing/unavailable/422 options behave cleanly.
    final secondVariant = dish.variantOptions.last;
    await tester.ensureVisible(
      find.text(
        '${secondVariant.name} · +₹${formatPaise(secondVariant.pricePaise)}',
      ),
    );
    await tester.tap(
      find.text(
        '${secondVariant.name} · +₹${formatPaise(secondVariant.pricePaise)}',
      ),
    );
    await tester.pumpAndSettle();
    expect(repo.quotes.last.variant, secondVariant.id);
    // Internal rule codes are moved out of main view into expandable Quote & fee details.
    expect(find.textContaining('DEMO_PACKAGING_V1'), findsNothing);
    await tester.ensureVisible(find.text('Quote & fee details'));
    await tester.tap(find.text('Quote & fee details'));
    await tester.pumpAndSettle();
    expect(find.textContaining('DEMO_PACKAGING_V1'), findsOneWidget);

    const unavailableOptionDish = Dish(
      'test-unavailable-opt',
      'tiffin',
      'Test Dosa',
      'Option availability test',
      'Dosa & Tiffins',
      'dosa',
      149,
      'Griddle',
      variantOptions: [
        DishOption('11111111-1111-4111-8111-111111111111', 'Regular', 0, true),
        DishOption(
          '22222222-2222-4222-8222-222222222222',
          'Giant',
          5000,
          false,
        ),
      ],
      addOnOptions: [
        DishOption(
          '33333333-3333-4333-8333-333333333333',
          'Sold-out Chutney',
          1000,
          false,
        ),
      ],
    );
    await host(
      tester,
      repo,
      const SingleChildScrollView(child: DishQuotePanel(unavailableOptionDish)),
    );
    final giantChip = tester.widget<ChoiceChip>(
      find.widgetWithText(ChoiceChip, 'Giant · +₹50 · unavailable'),
    );
    final soldOutAddOnChip = tester.widget<FilterChip>(
      find.widgetWithText(FilterChip, 'Sold-out Chutney · +₹10 · unavailable'),
    );
    expect(giantChip.onSelected, isNull);
    expect(soldOutAddOnChip.onSelected, isNull);

    // Missing options (empty lists) still quote successfully; 422 option error shows server message.
    final plainDish = Dish.fromJson(
      (fixture['items'] as List).first['quote']['item'],
    );
    await host(
      tester,
      repo,
      SingleChildScrollView(child: DishQuotePanel(plainDish)),
    );
    expect(find.text('Available sizes'), findsNothing);
    expect(find.text('Final payable'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    repo.quoteRejection = DioException(
      requestOptions: RequestOptions(path: '/pricing/quote'),
      response: Response(
        requestOptions: RequestOptions(path: '/pricing/quote'),
        statusCode: 422,
        data: {
          'error': {
            'message': 'Selected variant is unavailable or incompatible',
          },
        },
      ),
      type: DioExceptionType.badResponse,
    );
    await host(
      tester,
      repo,
      SingleChildScrollView(child: DishQuotePanel(plainDish)),
    );
    await tester.ensureVisible(
      find.text('Selected variant is unavailable or incompatible'),
    );
    expect(
      find.text('Selected variant is unavailable or incompatible'),
      findsOneWidget,
    );
  });
  testWidgets('comparison refreshes independent quotes and errors can retry', (
    tester,
  ) async {
    final repo = TestPricing();
    await host(
      tester,
      repo,
      Builder(
        builder: (context) => TextButton(
          onPressed: () => showMealComparison(context, 'madhapur', [
            'dosa',
            'st-karam-dosa',
          ]),
          child: const Text('Compare now'),
        ),
      ),
    );
    await tester.tap(find.text('Compare now'));
    await tester.pumpAndSettle();
    expect(repo.comparisons.single.ids, 'dosa,st-karam-dosa');
    expect(find.text('Compare meals'), findsOneWidget);
    expect(find.text('Final payable'), findsWidgets);
    await tester.pumpWidget(const SizedBox());
    repo.fail = true;
    await host(tester, repo, const SmartSearchScreen());
    await tester.scrollUntilVisible(
      find.text('Check again'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    repo.fail = false;
    await tester.tap(find.text('Check again'));
    await tester.pumpAndSettle();
    expect(find.text('Check again'), findsNothing);
  });
  test('Dish.photoKey maps distinct culinary varieties accurately', () {
    const cases = [
      ('Nellore Karam Dosa', 'dosa', 'karam-dosa'),
      ('Ghee Karam Masala Dosa', 'dosa', 'dosa'),
      ('Crispy Onion Rava Dosa', 'dosa', 'uttapam'),
      ('Crispy Medu Vada (2 pc)', 'idli', 'vada'),
      ('Charcoal-Smoked Dal Makhani', 'meals', 'dal-curry'),
      ('Artisanal Tandoori Bread Basket', 'paneer', 'roti-naan'),
      ('Chilled Mango Lassi', 'chai', 'cold-beverage'),
      ('Authentic Irani Chai', 'chai', 'chai'),
    ];
    for (final c in cases) {
      final dish = Dish('id', 'r', c.$1, 'desc', 'cat', c.$2, 149, 'sec');
      expect(dish.photoKey, c.$3);
    }
  });
  testWidgets(
    'SmartSearchScreen hides internal scores/paise, supports pagination, and preserves locality on filter clear',
    (tester) async {
      final repo = TestPricing()..totalOverride = 25;
      await host(tester, repo, const SmartSearchScreen());
      expect(find.textContaining('Value score'), findsNothing);
      expect(find.textContaining('paise'), findsNothing);
      expect(find.textContaining('page 1'), findsNothing);
      expect(find.textContaining('DEMO_'), findsNothing);
      await tester.scrollUntilVisible(
        find.text('Showing 3 of 25 meals'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.text('Showing 3 of 25 meals'), findsOneWidget);
      await tester.ensureVisible(find.text('Show more meals (22 remaining)'));
      await tester.tap(find.text('Show more meals (22 remaining)'));
      await tester.pumpAndSettle();
      expect(repo.searches.last.page, 2);

      // Clear filters inside filter sheet preserves chosen locality.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1200));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byTooltip('Meal filters'));
      await tester.tap(find.byTooltip('Meal filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('budget-input')), '150');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.text('Clear filters'));
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Show matching meals'));
      await tester.tap(find.text('Show matching meals'));
      await tester.pumpAndSettle();
      expect(repo.searches.last.budget, isNull);
      expect(repo.searches.last.area, 'madhapur');
    },
  );
  testWidgets('All five honest empty states render grounded recovery options', (
    tester,
  ) async {
    final repo = TestPricing();
    final baseDish = Dish.fromJson(
      (fixture['items'] as List).first['quote']['item'],
    );
    final seasonalDish = Dish(
      'dhd-shahi-haleem',
      baseDish.restaurantId,
      'Old City Mutton Haleem',
      baseDish.description,
      baseDish.category,
      'haleem',
      269,
      baseDish.section,
      availabilityStatus: 'UNAVAILABLE',
      availabilityReason:
          'Seasonal specialty — demo preview outside Ramzan season',
    );
    var increasedBudget = 0;
    var viewedAboveBudget = false;
    var removedTimeLimit = false;
    var changedLocality = false;

    for (final diag in [
      EmptyDiagnosis(
        reason: EmptyReason.seasonalOrUnavailable,
        unavailable: [seasonalDish],
      ),
      const EmptyDiagnosis(reason: EmptyReason.noKitchensInLocality),
      const EmptyDiagnosis(
        reason: EmptyReason.exceedsBudget,
        cheapestTotalPaise: 17400,
        alternativeCount: 4,
      ),
      const EmptyDiagnosis(
        reason: EmptyReason.exceedsTime,
        fastestMinutes: 25,
        alternativeCount: 6,
      ),
      const EmptyDiagnosis(reason: EmptyReason.noMatchingDishes),
    ]) {
      await tester.pumpWidget(const SizedBox());
      await host(
        tester,
        repo,
        SingleChildScrollView(
          child: SmartEmptyState(
            areaName: 'Madhapur',
            queryText: 'haleem',
            budget: 15000,
            maxMinutes: 20,
            diagnosis: diag,
            onResetFilters: () {},
            onResetAll: () {},
            onOpenLocality: () => changedLocality = true,
            onIncreaseBudget: (v) => increasedBudget = v,
            onViewAboveBudget: () => viewedAboveBudget = true,
            onRemoveTimeLimit: () => removedTimeLimit = true,
          ),
        ),
      );
      if (diag.reason == EmptyReason.seasonalOrUnavailable) {
        expect(find.text('Seasonal or currently unavailable'), findsOneWidget);
        expect(find.textContaining('Ramzan season'), findsWidgets);
      } else if (diag.reason == EmptyReason.noKitchensInLocality) {
        await tester.tap(find.text('Change locality'));
        expect(changedLocality, isTrue);
      } else if (diag.reason == EmptyReason.exceedsBudget) {
        await tester.tap(find.text('Increase budget to ₹174'));
        await tester.tap(find.text('View 4 alternatives above ₹150'));
        expect(increasedBudget, 17400);
        expect(viewedAboveBudget, isTrue);
      } else if (diag.reason == EmptyReason.exceedsTime) {
        await tester.tap(find.text('Remove delivery-time filter'));
        expect(removedTimeLimit, isTrue);
      } else {
        expect(find.text('No matching dishes for "haleem".'), findsOneWidget);
      }
    }
  });
  for (final width in [360.0, 393.0, 430.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'smart results & comparison layout $width ${brightness.name}',
        (tester) async {
          tester.view.physicalSize = Size(width, 850);
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.resetPhysicalSize);
          addTearDown(tester.view.resetDevicePixelRatio);
          await host(
            tester,
            TestPricing(),
            const SmartSearchScreen(),
            brightness: brightness,
          );
          for (var i = 0; i < 6; i++) {
            await tester.drag(
              find.byType(Scrollable).first,
              const Offset(0, -400),
            );
            await tester.pumpAndSettle();
            expect(tester.takeException(), isNull);
          }
          await tester.pumpWidget(const SizedBox());
          await host(
            tester,
            TestPricing(),
            Builder(
              builder: (context) => TextButton(
                onPressed: () => showMealComparison(context, 'madhapur', [
                  'dosa',
                  'gtc-ghee-masala-dosa',
                ], bestValueDishId: 'dosa'),
                child: const Text('Open compare'),
              ),
            ),
            brightness: brightness,
          );
          await tester.tap(find.text('Open compare'));
          await tester.pumpAndSettle();
          expect(find.text('Compare meals'), findsOneWidget);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }
}
