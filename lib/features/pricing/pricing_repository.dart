import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../catalog/catalog.dart';

class MealQuote {
  final Dish dish;
  final Restaurant restaurant;
  final Map<String, int> amounts;
  final int quantity, minutes;
  final String? variantId, variantName;
  final List<String> addOnNames, ruleCodes;
  final String areaName, fingerprint, ruleVersion, notice, taxNotice;
  final DateTime expiresAt;
  MealQuote.fromJson(Map<String, dynamic> j)
    : dish = Dish.fromJson(j['item']),
      restaurant = Restaurant.fromJson(j['item']['restaurant']),
      amounts = {
        for (final key in [
          'basePaise',
          'variantPaise',
          'addOnPaise',
          'subtotalPaise',
          'packagingPaise',
          'deliveryPaise',
          'platformPaise',
          'discountPaise',
          'taxPaise',
          'finalPayablePaise',
        ])
          key: j[key] as int,
      },
      quantity = j['quantity'] as int,
      minutes = j['estimatedMinutes'] as int,
      variantId = j['selectedVariant']?['id'] as String?,
      variantName = j['selectedVariant']?['name'] as String?,
      addOnNames = (j['selectedAddOns'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((a) => a['name'] as String?)
          .whereType<String>()
          .toList(),
      ruleCodes = (j['adjustments'] as List? ?? [])
          .whereType<Map<String, dynamic>>()
          .map((a) => a['ruleCode'] as String?)
          .whereType<String>()
          .toList(),
      areaName = j['area']['name'] as String,
      fingerprint = j['quoteFingerprint'] as String,
      ruleVersion = j['pricingRuleVersion'] as String,
      notice = j['notice'] as String,
      taxNotice = j['taxNotice'] as String,
      expiresAt = DateTime.parse(j['expiresAt'] as String);
  int get total => amounts['finalPayablePaise']!;
}

class SmartMeal {
  final MealQuote quote;
  final List<String> explanations;
  final int score;
  SmartMeal.fromJson(Map<String, dynamic> j)
    : quote = MealQuote.fromJson(j['quote']),
      explanations = (j['explanations'] as List).cast<String>(),
      score = j['valueScore'] as int;
}

class SmartPage {
  final List<SmartMeal> items;
  final int total, page;
  SmartPage.fromJson(Map<String, dynamic> j)
    : items = (j['items'] as List).map((x) => SmartMeal.fromJson(x)).toList(),
      total = j['total'],
      page = j['page'];
}

typedef SmartQuery = ({
  String text,
  String area,
  String? category,
  String? cuisine,
  String? restaurant,
  int? budget,
  bool? vegetarian,
  int? minutes,
  double? rating,
  String sort,
  int page,
});
typedef QuoteRequest = ({
  String item,
  String restaurant,
  String area,
  String? variant,
  String addOns,
  int quantity,
  String? promotion,
});
typedef CompareRequest = ({String area, String ids});

enum EmptyReason {
  seasonalOrUnavailable,
  noKitchensInLocality,
  exceedsBudget,
  exceedsTime,
  noMatchingDishes,
}

class EmptyDiagnosis {
  final EmptyReason reason;
  final List<Dish> unavailable;
  final int? cheapestTotalPaise;
  final int? fastestMinutes;
  final int? alternativeCount;
  const EmptyDiagnosis({
    required this.reason,
    this.unavailable = const [],
    this.cheapestTotalPaise,
    this.fastestMinutes,
    this.alternativeCount,
  });
}

class PricingRepository {
  final Dio dio;
  PricingRepository(this.dio);
  String get base => dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  Future<SmartPage> search(
    SmartQuery q,
    CancelToken token, {
    int limit = 12,
  }) async {
    final response = await dio.get(
      '$base/catalog/smart-search',
      cancelToken: token,
      queryParameters: {
        'q': q.text,
        'area': q.area,
        'page': q.page,
        'limit': limit,
        'sort': q.sort,
        'category': ?q.category,
        'cuisine': ?q.cuisine,
        'restaurantId': ?q.restaurant,
        'maxPayablePaise': ?q.budget,
        'vegetarian': ?q.vegetarian,
        'maxMinutes': ?q.minutes,
        'minRating': ?q.rating,
      },
    );
    return SmartPage.fromJson(response.data['data']);
  }

  Future<EmptyDiagnosis> diagnoseEmpty(SmartQuery q, CancelToken token) async {
    final unavailable = await unavailableMatches(q.text, q.area, token);
    if (unavailable.isNotEmpty) {
      return EmptyDiagnosis(
        reason: EmptyReason.seasonalOrUnavailable,
        unavailable: unavailable,
      );
    }
    final kitchens = await choices(
      'restaurants?area=${Uri.encodeComponent(q.area)}&limit=1',
      token,
    );
    if (kitchens.isEmpty) {
      return const EmptyDiagnosis(reason: EmptyReason.noKitchensInLocality);
    }
    if (q.budget != null) {
      final unbudgeted = await search(
        (
          text: q.text,
          area: q.area,
          category: q.category,
          cuisine: q.cuisine,
          restaurant: q.restaurant,
          budget: null,
          vegetarian: q.vegetarian,
          minutes: q.minutes,
          rating: q.rating,
          sort: 'price',
          page: 1,
        ),
        token,
        limit: 1,
      );
      if (unbudgeted.items.isNotEmpty) {
        return EmptyDiagnosis(
          reason: EmptyReason.exceedsBudget,
          cheapestTotalPaise: unbudgeted.items.first.quote.total,
          alternativeCount: unbudgeted.total,
        );
      }
    }
    if (q.minutes != null) {
      final untimed = await search(
        (
          text: q.text,
          area: q.area,
          category: q.category,
          cuisine: q.cuisine,
          restaurant: q.restaurant,
          budget: q.budget,
          vegetarian: q.vegetarian,
          minutes: null,
          rating: q.rating,
          sort: 'time',
          page: 1,
        ),
        token,
        limit: 1,
      );
      if (untimed.items.isNotEmpty) {
        return EmptyDiagnosis(
          reason: EmptyReason.exceedsTime,
          fastestMinutes: untimed.items.first.quote.minutes,
          alternativeCount: untimed.total,
        );
      }
    }
    return const EmptyDiagnosis(reason: EmptyReason.noMatchingDishes);
  }

  Future<MealQuote> quote(QuoteRequest q, CancelToken token) async {
    final response = await dio.post(
      '$base/pricing/quote',
      cancelToken: token,
      data: {
        'menuItemId': q.item,
        'restaurantId': q.restaurant,
        'area': q.area,
        'quantity': q.quantity,
        'variantId': ?q.variant,
        'addOnIds': q.addOns.isEmpty ? <String>[] : q.addOns.split(','),
        'promotion': ?q.promotion,
      },
    );
    return MealQuote.fromJson(response.data['data']);
  }

  Future<List<MealQuote>> compare(CompareRequest q, CancelToken token) async {
    final response = await dio.post(
      '$base/pricing/compare',
      cancelToken: token,
      data: {'area': q.area, 'itemIds': q.ids.split(',')},
    );
    return (response.data['data']['items'] as List)
        .map((j) => MealQuote.fromJson(j))
        .toList();
  }

  Future<List<({String id, String name})>> choices(
    String path,
    CancelToken token,
  ) async {
    final response = await dio.get('$base/$path', cancelToken: token);
    final data = response.data['data'];
    final rows = data is List ? data : data['items'] as List;
    return rows
        .map<({String id, String name})>(
          (j) => (id: j['id'] as String, name: j['name'] as String),
        )
        .toList();
  }

  Future<List<Dish>> unavailableMatches(
    String text,
    String area,
    CancelToken token,
  ) async {
    if (text.trim().isEmpty) return const [];
    final response = await dio.get(
      '$base/catalog/search',
      cancelToken: token,
      queryParameters: {'q': text.trim(), 'area': area, 'limit': 6},
    );
    final rows = (response.data['data']['items'] as List? ?? [])
        .whereType<Map<String, dynamic>>();
    return rows
        .map(Dish.fromJson)
        .where((d) => d.availabilityStatus != 'AVAILABLE')
        .toList();
  }
}

final pricingRepositoryProvider = Provider(
  (ref) => PricingRepository(ref.watch(apiClientProvider)),
);
CancelToken pricingToken(Ref ref) {
  final token = CancelToken();
  ref.onDispose(() => token.cancel());
  return token;
}

final smartSearchProvider = FutureProvider.autoDispose
    .family<SmartPage, SmartQuery>(
      (ref, q) =>
          ref.watch(pricingRepositoryProvider).search(q, pricingToken(ref)),
    );
final quoteProvider = FutureProvider.autoDispose
    .family<MealQuote, QuoteRequest>(
      (ref, q) =>
          ref.watch(pricingRepositoryProvider).quote(q, pricingToken(ref)),
    );
final compareProvider = FutureProvider.autoDispose
    .family<List<MealQuote>, CompareRequest>(
      (ref, q) =>
          ref.watch(pricingRepositoryProvider).compare(q, pricingToken(ref)),
    );
final cuisineChoicesProvider = FutureProvider.autoDispose(
  (ref) => ref
      .watch(pricingRepositoryProvider)
      .choices('cuisines', pricingToken(ref)),
);
final kitchenChoicesProvider = FutureProvider.autoDispose
    .family<List<({String id, String name})>, String>(
      (ref, area) => ref
          .watch(pricingRepositoryProvider)
          .choices(
            'restaurants?area=${Uri.encodeComponent(area)}&limit=50',
            pricingToken(ref),
          ),
    );
final unavailableCatalogProvider = FutureProvider.autoDispose
    .family<List<Dish>, ({String text, String area})>(
      (ref, q) => ref
          .watch(pricingRepositoryProvider)
          .unavailableMatches(q.text, q.area, pricingToken(ref)),
    );
final emptyDiagnosisProvider = FutureProvider.autoDispose
    .family<EmptyDiagnosis, SmartQuery>(
      (ref, q) => ref
          .watch(pricingRepositoryProvider)
          .diagnoseEmpty(q, pricingToken(ref)),
    );
