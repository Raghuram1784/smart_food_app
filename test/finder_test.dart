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
import 'package:smart_food_demo/features/finder/finder_screen.dart';
import 'package:smart_food_demo/features/location/delivery_destination.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce;

/// Deterministic server responses. The app must display exactly these server
/// amounts: it never computes totals itself.
Json rec({
  String id = 'mini',
  String name = 'Mini Chicken Dum Biryani',
  String restaurantId = 'kitchen',
  int food = 10900,
  int total = 14400,
  int? budget = 15000,
  String status = 'WITHIN_BUDGET',
  String match = 'EXACT',
  Json? nutrition,
}) =>
    {
      'menuItemId': id,
      'restaurantId': restaurantId,
      'restaurantName': 'Deccan Handi & Dum',
      'locality': 'Gachibowli, Hyderabad',
      'name': name,
      'description': 'Half portion biryani',
      'imageKey': 'chicken-biryani',
      'isVegetarian': false,
      'quantity': 1,
      'variant': null,
      'hasVariantChoices': false,
      'hasAddOns': false,
      'pricing': {'foodPaise': food, 'discountPaise': 0, 'packagingPaise': 1000, 'deliveryPaise': 2000, 'platformPaise': 500, 'taxPaise': 0, 'totalPaise': total},
      'budgetPaise': budget,
      'budgetStatus': status,
      'budgetDifferencePaise': budget == null ? null : total - budget,
      'nutrition': nutrition,
      'tasteTags': ['spicy', 'aromatic'],
      'spiceLevel': 2,
      'matchType': match,
      'reasons': ['Exact dish match', 'Matches spicy preference'],
    };

const _n = {'servingDescription': '1 half plate', 'servingGrams': 200, 'caloriesKcal': 350, 'proteinG': 17, 'carbsG': 40, 'fatG': 13, 'basis': 'ESTIMATE', 'source': 'Estimate'};

Json results({String status = 'RESULTS', List<Json>? exact, List<Json>? near, List<Json>? similar, String? notice}) => {
      'conversationId': '11111111-1111-4111-8111-111111111111',
      'status': status,
      'reply': 'I found 1 option for spicy chicken biryani within your ₹150 total budget.',
      'interpreter': 'gemini',
      'aiNotice': notice,
      'intentSummary': 'spicy chicken biryani',
      'result': {
        'status': 'EXACT_MATCHES',
        'area': {'id': 'gachibowli', 'name': 'Gachibowli, Hyderabad'},
        'budgetPaise': 15000,
        'exact': exact ?? [rec(nutrition: _n, total: 15000, status: 'EXACT_BUDGET')],
        'nearBudget': near ?? [rec(id: 'pulao', name: 'Chicken Pulao', food: 12900, total: 16400, status: 'ABOVE_BUDGET', match: 'NEAR_BUDGET')],
        'similar': similar ?? [],
        'excludedForMissingNutrition': 0,
        'notice': 'Synthetic demo restaurants with illustrative prices.',
      },
    };

class FinderFake extends FakeCommerce {
  final asks = <Json>[];
  final List<Object Function(Json)> replies = [];
  int? quoteTotal;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path == 'food-finder/ask') {
      calls.add('$method $path');
      asks.add(data!);
      final next = replies.isEmpty ? (Json _) => results() : replies.removeAt(0);
      final out = next(data);
      if (out is Exception || out is Error) throw out;
      return out;
    }
    if (path == 'pricing/quote') {
      calls.add('$method $path');
      return {'finalPayablePaise': quoteTotal ?? 0};
    }
    if (path.startsWith('food-finder/conversations/')) {
      calls.add('$method $path');
      return {'ended': true};
    }
    return super.request(method, path, data);
  }
}

Future<void> _mount(WidgetTester tester, FinderFake repo, {Size size = const Size(393, 852), double text = 1, Brightness brightness = Brightness.light, bool withArea = true}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
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
      deliveryServiceAreaProvider.overrideWithValue(withArea ? const ServiceArea('gachibowli', 'Gachibowli', 'Hyderabad') : null),
    ],
    child: MediaQuery(
      data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)),
      child: MaterialApp.router(theme: appTheme(brightness), routerConfig: router),
    ),
  ));
  await tester.pumpAndSettle();
}

Future<void> _ask(WidgetTester tester, String text) async {
  await tester.enterText(find.byKey(const ValueKey('finder-input')), text);
  await tester.tap(find.byKey(const ValueKey('finder-send')));
  await tester.pump();
  await tester.pumpAndSettle();
}

void main() {
  _registerFeeToggle();
  testWidgets('welcome state, starter prompt, exact and near-budget sections with server totals', (tester) async {
    final repo = FinderFake();
    await _mount(tester, repo);
    expect(find.text('Tell us what you\'re craving'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('prompt-Chicken Biryani under ₹150')));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repo.asks.single['message'], 'Chicken Biryani under ₹150');
    expect(repo.asks.single['area'], 'gachibowli', reason: 'selected address area sent for real fees');
    expect(find.byKey(const ValueKey('section-exact')), findsOneWidget);
    expect(find.text('Exact budget match'), findsOneWidget);
    expect(find.text('350 kcal'), findsOneWidget);
    expect(find.text('17 g protein'), findsOneWidget);
    expect(find.textContaining('Estimate per 1 half plate'), findsOneWidget);
    await tester.scrollUntilVisible(find.byKey(const ValueKey('section-near')), 300, scrollable: find.byType(Scrollable).first);
    expect(find.text('₹14 above budget'), findsOneWidget, reason: 'over-budget never styled as within budget');
    expect(find.text('Within budget'), findsNothing);
    expect(find.text('₹164'), findsOneWidget, reason: 'total shown exactly as the server computed it');
    expect(tester.takeException(), isNull);
  });

  for (final b in Brightness.values) {
    testWidgets('360px at 150% text (${b.name}): chat, cards and composer never overflow', (tester) async {
      final repo = FinderFake();
      await _mount(tester, repo, size: const Size(360, 740), text: 1.5, brightness: b);
      expect(tester.takeException(), isNull);
      await _ask(tester, 'I want spicy Chicken Biryani under ₹150');
      expect(tester.takeException(), isNull);
      await tester.scrollUntilVisible(find.byKey(const ValueKey('finder-refinements')), 300, scrollable: find.byType(Scrollable).first);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('missing nutrition shows "Nutrition unavailable", never zeros', (tester) async {
    final repo = FinderFake()..replies.add((_) => results(exact: [rec(nutrition: null)], near: []));
    await _mount(tester, repo);
    await _ask(tester, 'biryani');
    expect(find.text('Nutrition unavailable'), findsOneWidget);
    expect(find.textContaining('0 kcal'), findsNothing);
  });

  testWidgets('over-budget item asks before adding; cancel adds nothing, confirm adds once', (tester) async {
    final repo = FinderFake()
      ..quoteTotal = 16400
      ..replies.add((_) => results(exact: [], near: [rec(id: 'pulao', name: 'Chicken Pulao', total: 16400, status: 'ABOVE_BUDGET', match: 'NEAR_BUDGET')]));
    await _mount(tester, repo);
    await _ask(tester, 'chicken biryani under ₹150');
    await tester.scrollUntilVisible(find.byKey(const ValueKey('finder-add-1')), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('finder-add-1')), matching: find.byKey(const ValueKey('add-to-cart'))));
    await tester.pumpAndSettle();
    expect(find.text('Above your budget'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'POST cart/items'), isEmpty);
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('finder-add-1')), matching: find.byKey(const ValueKey('add-to-cart'))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('finder-confirm-add')));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'POST pricing/quote').length, 1, reason: 're-quoted before adding');
    expect(repo.calls.where((c) => c == 'POST cart/items').length, 1);
    expect(find.byKey(const ValueKey('cart-added-toast')), findsOneWidget, reason: 'success only after the API');
    await tester.pump(const Duration(seconds: 5));
    await tester.pumpAndSettle();
  });

  testWidgets('a changed price is shown and must be confirmed before adding', (tester) async {
    final repo = FinderFake()..quoteTotal = 15900;
    await _mount(tester, repo);
    await _ask(tester, 'chicken biryani under ₹150');
    await tester.ensureVisible(find.descendant(of: find.byKey(const ValueKey('finder-add-1')), matching: find.byKey(const ValueKey('add-to-cart'))));
    await tester.pumpAndSettle();
    await tester.tap(find.descendant(of: find.byKey(const ValueKey('finder-add-1')), matching: find.byKey(const ValueKey('add-to-cart'))));
    await tester.pumpAndSettle();
    expect(find.text('Price updated'), findsOneWidget);
    expect(find.textContaining('changed from ₹150 to ₹159'), findsOneWidget);
    expect(find.descendant(of: find.byType(AlertDialog), matching: find.textContaining('above your ₹150 budget')), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(repo.calls.where((c) => c == 'POST cart/items'), isEmpty);
  });

  testWidgets('no delivery area: shows area chips and re-runs the search for the chosen area', (tester) async {
    final repo = FinderFake()
      ..replies.add((_) => {
            'conversationId': '22222222-2222-4222-8222-222222222222',
            'status': 'NEEDS_AREA',
            'reply': 'Which area should I deliver to?',
            'interpreter': 'gemini',
            'areas': [
              {'id': 'gachibowli', 'name': 'Gachibowli, Hyderabad'},
              {'id': 'madhapur', 'name': 'Madhapur, Hyderabad'},
            ],
          });
    await _mount(tester, repo, withArea: false);
    await _ask(tester, 'biryani under ₹150');
    expect(repo.asks.first.containsKey('area'), isFalse);
    await tester.tap(find.text('Madhapur'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repo.asks.last['area'], 'madhapur');
    expect(repo.asks.last['refresh'], true);
    expect(repo.asks.last['conversationId'], '22222222-2222-4222-8222-222222222222');
    expect(find.byKey(const ValueKey('section-exact')), findsOneWidget);
  });

  testWidgets('errors offer retry; an expired conversation restarts transparently', (tester) async {
    final repo = FinderFake()
      ..replies.add((_) => DioException(requestOptions: RequestOptions(), type: DioExceptionType.connectionError))
      ..replies.add((_) => results())
      ..replies.add((_) => DioException(requestOptions: RequestOptions(), response: Response(requestOptions: RequestOptions(), statusCode: 404)))
      ..replies.add((_) => results());
    await _mount(tester, repo);
    await _ask(tester, 'biryani');
    expect(find.byKey(const ValueKey('finder-error')), findsOneWidget);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('finder-error')), findsNothing);
    expect(find.byKey(const ValueKey('section-exact')), findsOneWidget);
    await _ask(tester, 'show cheaper options');
    expect(repo.asks.last.containsKey('conversationId'), isFalse, reason: 'restarted without the expired id');
    await tester.scrollUntilVisible(find.text('Your earlier search expired, so I started a new one.'), -300, scrollable: find.byType(Scrollable).first);
    expect(find.text('Your earlier search expired, so I started a new one.'), findsOneWidget);
  });

  testWidgets('AI fallback notice is shown; refinement chips send follow-ups in the same conversation', (tester) async {
    final repo = FinderFake()..replies.add((_) => results(notice: 'The AI service is busy right now, so I used basic keyword understanding.'));
    await _mount(tester, repo);
    await _ask(tester, 'biryani');
    expect(find.byKey(const ValueKey('finder-ai-notice')), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Show cheaper options'), 300, scrollable: find.byType(Scrollable).first);
    await tester.tap(find.text('Show cheaper options'));
    await tester.pump();
    await tester.pumpAndSettle();
    expect(repo.asks.last['message'], 'Show cheaper options');
    expect(repo.asks.last['conversationId'], '11111111-1111-4111-8111-111111111111');
  });

  testWidgets('New search clears the chat and ends the server conversation', (tester) async {
    final repo = FinderFake();
    await _mount(tester, repo);
    await _ask(tester, 'biryani');
    await tester.tap(find.byKey(const ValueKey('finder-reset')));
    await tester.pumpAndSettle();
    expect(find.text('Tell us what you\'re craving'), findsOneWidget);
    expect(repo.calls, contains('DELETE food-finder/conversations/11111111-1111-4111-8111-111111111111'));
  });

  testWidgets('Home entry card opens the finder', (tester) async {
    final router = GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const Scaffold(body: Padding(padding: EdgeInsets.all(20), child: FinderEntryCard()))),
      GoRoute(path: '/finder', builder: (_, _) => const Scaffold(body: Text('Finder route'))),
    ]);
    addTearDown(router.dispose);
    await tester.pumpWidget(MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router));
    expect(find.text('Find food with AI'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('finder-entry')));
    await tester.pumpAndSettle();
    expect(find.text('Finder route'), findsOneWidget);
  });
}

void _registerFeeToggle() {
  testWidgets('fee breakdown: menu price and total always visible; fee details expand on tap', (tester) async {
    final repo = FinderFake()..replies.add((_) => results(exact: [rec(nutrition: _n, total: 14400)], near: []));
    await _mount(tester, repo);
    await _ask(tester, 'chicken biryani under ₹150');
    expect(find.text('Menu price'), findsOneWidget);
    expect(find.text('₹144'), findsOneWidget, reason: 'total payable always shown');
    expect(find.text('₹35'), findsOneWidget, reason: 'fees summarised in one line');
    expect(find.textContaining('Packaging'), findsNothing, reason: 'collapsed by default');
    await tester.tap(find.byKey(const ValueKey('finder-fees-toggle')));
    await tester.pumpAndSettle();
    expect(find.textContaining('Packaging'), findsOneWidget);
    expect(find.textContaining('Delivery fee'), findsOneWidget);
    expect(find.text('None configured'), findsOneWidget, reason: 'no invented tax');
  });
}
