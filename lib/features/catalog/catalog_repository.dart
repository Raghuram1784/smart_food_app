import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'catalog.dart' as local;
import 'catalog.dart' show Dish, Restaurant;
import 'diet_preference.dart';

class FoodCategory {
  final String id, name, image;
  const FoodCategory(this.id, this.name, this.image);
}

class CatalogPage {
  final List<Dish> items;
  final List<Restaurant> restaurants;
  final int total, page;
  const CatalogPage(this.items, this.restaurants, this.total, this.page);
}

class HomeCatalog {
  final List<Restaurant> restaurants;
  final List<Dish> dishes;
  final List<FoodCategory> categories;
  const HomeCatalog(this.restaurants, this.dishes, this.categories);
}

class RestaurantMenu {
  final Restaurant restaurant;
  final List<Dish> items;
  const RestaurantMenu(this.restaurant, this.items);
}

typedef SearchQuery = ({
  String text,
  String? category,
  String? area,
  bool affordable,
  int page,
});

abstract class CatalogRepository {
  bool get offline;
  Future<List<ServiceArea>> areas(CancelToken token);
  Future<List<FoodCategory>> categories(CancelToken token);
  Future<HomeCatalog> home(String? area, CancelToken token, {String? diet});
  Future<CatalogPage> search(SearchQuery query, CancelToken token);
  Future<RestaurantMenu> menu(String id, CancelToken token);
  Future<Dish> item(String id, CancelToken token);
}

class ApiCatalogRepository implements CatalogRepository {
  final Dio dio;
  ApiCatalogRepository(this.dio);
  @override
  bool get offline => false;
  Future<dynamic> _get(
    String path,
    CancelToken token, [
    Map<String, dynamic>? query,
  ]) async {
    // Normalize a trailing slash while retaining the configured API prefix.
    final base = dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    final response = await dio.get<dynamic>(
      '$base/$path',
      queryParameters: query,
      cancelToken: token,
    );
    return response.data['data'];
  }

  @override
  Future<List<ServiceArea>> areas(CancelToken token) async {
    final raw = await _get('areas', token);
    final list = raw is List ? raw : (raw['items'] as List);
    return list
        .map((j) => ServiceArea.fromJson(j as Map<String, dynamic>))
        .toList();
  }

  @override
  Future<List<FoodCategory>> categories(CancelToken token) async =>
      (await _get('categories', token) as List)
          .map((j) => FoodCategory(j['id'], j['name'], j['imageKey']))
          .toList();
  @override
  Future<HomeCatalog> home(String? area, CancelToken token, {String? diet}) async {
    final results = await Future.wait<dynamic>([
      _get('restaurants', token, {'limit': 50, 'area': ?area, 'diet': ?diet}),
      _get('catalog/search', token, {'limit': 50, 'area': ?area, 'diet': ?diet}),
      categories(token),
    ]);
    return HomeCatalog(
      (results[0]['items'] as List).map((j) => Restaurant.fromJson(j)).toList(),
      (results[1]['items'] as List).map((j) => Dish.fromJson(j)).toList(),
      results[2] as List<FoodCategory>,
    );
  }

  @override
  Future<CatalogPage> search(SearchQuery query, CancelToken token) async {
    final j = await _get('catalog/search', token, {
      'q': query.text.trim(),
      'page': query.page,
      'limit': 20,
      if (query.category != null) 'category': query.category,
      if (query.area != null) 'area': query.area,
      if (query.affordable) 'maxPricePaise': 25000,
    });
    final rows = j['items'] as List;
    final kitchens = <String, Restaurant>{};
    for (final row in rows) {
      final restaurant = Restaurant.fromJson(row['restaurant']);
      kitchens[restaurant.id] = restaurant;
    }
    return CatalogPage(
      rows.map((v) => Dish.fromJson(v)).toList(),
      kitchens.values.toList(),
      j['total'] as int,
      j['page'] as int,
    );
  }

  @override
  Future<RestaurantMenu> menu(String id, CancelToken token) async {
    final j = await _get('restaurants/${Uri.encodeComponent(id)}/menu', token);
    return RestaurantMenu(
      Restaurant.fromJson(j['restaurant']),
      (j['sections'] as List)
          .expand((s) => s['items'] as List)
          .map((d) => Dish.fromJson(d))
          .toList(),
    );
  }

  @override
  Future<Dish> item(String id, CancelToken token) async =>
      Dish.fromJson(await _get('menu-items/${Uri.encodeComponent(id)}', token));
}

// Selected explicitly by CATALOG_MODE=offline or a test override. Never a network fallback.
class OfflineCatalogRepository implements CatalogRepository {
  @override
  bool get offline => true;
  Restaurant _restaurant(Restaurant r) => Restaurant(
    r.id,
    r.name,
    r.cuisine,
    r.description,
    r.image,
    r.time,
    r.rating,
    startingPricePaise: local.dishes
        .where((d) => d.restaurantId == r.id)
        .map((d) => d.pricePaise)
        .reduce((a, b) => a < b ? a : b),
    operatingStatus: r.operatingStatus,
    deliveryAvailable: r.deliveryAvailable,
    localityName: r.localityName,
    serviceAreaNames: r.serviceAreaNames,
  );
  Dish _dish(Dish d) => Dish(
    d.id,
    d.restaurantId,
    d.name,
    d.description,
    d.category,
    d.image,
    d.price,
    d.section,
    availabilityStatus: d.availabilityStatus,
    restaurantName: local.restaurantFor(d.restaurantId).name,
    availabilityReason: d.availabilityReason,
    variants: d.variants,
    addOns: d.addOns,
  );
  @override
  Future<List<ServiceArea>> areas(CancelToken token) async =>
      ServiceArea.hyderabadAreas;
  @override
  Future<List<FoodCategory>> categories(CancelToken token) async => local
      .categories
      .entries
      .map((e) => FoodCategory(e.key.toLowerCase(), e.key, e.value))
      .toList();
  @override
  Future<HomeCatalog> home(String? area, CancelToken token, {String? diet}) async {
    final dishes = local.dishes.map(_dish).where((d) => diet == null || d.isVegetarian == (diet == 'veg')).toList();
    return HomeCatalog(local.restaurants.map(_restaurant).toList(), dishes, await categories(token));
  }
  @override
  Future<RestaurantMenu> menu(String id, CancelToken token) async =>
      RestaurantMenu(
        _restaurant(local.restaurantFor(id)),
        local.dishes.where((d) => d.restaurantId == id).map(_dish).toList(),
      );
  @override
  Future<Dish> item(String id, CancelToken token) async =>
      _dish(local.dishes.firstWhere((d) => d.id == id));
  @override
  Future<CatalogPage> search(SearchQuery query, CancelToken token) async {
    final category = local.categories.keys
        .where((c) => c.toLowerCase() == query.category)
        .firstOrNull;
    final items = local.searchDishes(
      query.text,
      category,
      affordable: query.affordable,
    );
    return CatalogPage(
      items.skip((query.page - 1) * 20).take(20).map(_dish).toList(),
      local.restaurants
          .where((r) => items.any((d) => d.restaurantId == r.id))
          .map(_restaurant)
          .toList(),
      items.length,
      query.page,
    );
  }
}

final catalogRepositoryProvider = Provider<CatalogRepository>((ref) {
  const offline = String.fromEnvironment('CATALOG_MODE') == 'offline';
  return offline
      ? OfflineCatalogRepository()
      : ApiCatalogRepository(ref.watch(apiClientProvider));
});
CancelToken _token(Ref ref) {
  final token = CancelToken();
  ref.onDispose(() => token.cancel('Screen disposed or query superseded'));
  return token;
}

final areasProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(catalogRepositoryProvider).areas(_token(ref)),
);
// Home lists every kitchen; delivery eligibility for the confirmed destination
// is shown per restaurant (serviceabilityProvider) rather than hiding kitchens.
final homeCatalogProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(catalogRepositoryProvider).home(
    null,
    _token(ref),
    diet: ref.watch(dietPreferenceProvider).api,
  ),
);
final categoriesProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(catalogRepositoryProvider).categories(_token(ref)),
);
final restaurantMenuProvider = FutureProvider.autoDispose
    .family<RestaurantMenu, String>(
      (ref, id) => ref.watch(catalogRepositoryProvider).menu(id, _token(ref)),
    );
final dishProvider = FutureProvider.autoDispose.family<Dish, String>(
  (ref, id) => ref.watch(catalogRepositoryProvider).item(id, _token(ref)),
);
final catalogSearchProvider = FutureProvider.autoDispose
    .family<CatalogPage, SearchQuery>(
      (ref, query) =>
          ref.watch(catalogRepositoryProvider).search(query, _token(ref)),
    );
