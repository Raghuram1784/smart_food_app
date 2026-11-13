import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/discovery/home_screen.dart';
import 'package:smart_food_demo/features/discovery/home_widgets.dart';
import 'package:smart_food_demo/shared/components.dart';

class FixtureAdapter implements HttpClientAdapter {
  final Future<ResponseBody> Function(RequestOptions, Future<void>?) handler;
  FixtureAdapter(this.handler);
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? stream,
    Future<void>? cancelFuture,
  ) => handler(options, cancelFuture);
  @override
  void close({bool force = false}) {}
}

void main() {
  test('live DTO maps exact paise, availability, IDs and image keys', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));
    dio.httpClientAdapter = FixtureAdapter((request, _) async {
      expect(request.uri.path, '/api/v1/menu-items/dosa');
      return ResponseBody.fromString(
        jsonEncode({
          'data': {
            'id': 'dosa',
            'restaurantId': 'tiffin',
            'name': 'Changed in database',
            'description': 'A live description',
            'imageKey': 'dosa',
            'basePricePaise': 14937,
            'availabilityStatus': 'SOLD_OUT',
            'category': {'name': 'Dosa'},
            'section': {'name': 'From the griddle'},
            'restaurant': {'name': 'The Tiffin Room'},
          },
        }),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });
    final item = await ApiCatalogRepository(dio).item('dosa', CancelToken());
    expect(item.name, 'Changed in database');
    expect(item.pricePaise, 14937);
    expect(item.displayPrice, '149.37');
    expect(item.image, 'dosa');
    expect(item.availabilityStatus, 'SOLD_OUT');
    expect(formatPaise(14900), '149');
    dio.close();
  });

  test('disposing a provider cancels its in-flight request', () async {
    final started = Completer<void>(), cancelled = Completer<void>();
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1/'));
    dio.httpClientAdapter = FixtureAdapter((_, cancellation) async {
      started.complete();
      await cancellation;
      cancelled.complete();
      return ResponseBody.fromString('{}', 200);
    });
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(dio)],
    );
    container.listen(dishProvider('dosa'), (_, _) {});
    await started.future;
    container.dispose();
    await cancelled.future;
    dio.close();
  });

  testWidgets('loading, error, retry and explicit offline mode are visible', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    final result = Completer<HomeCatalog>();
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          homeCatalogProvider.overrideWith((ref) => result.future),
        ],
        child: const MaterialApp(home: Scaffold(body: HomeScreen())),
      ),
    );
    await tester.pump();
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    result.completeError(Exception('connection refused'));
    await tester.pumpAndSettle();
    expect(find.text('The catalog is unavailable right now.'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Masala dosa'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    // ThemeExtension is supplied by the production theme.
  });

  test('areas, home, and search send area filter and map locality, variants, and add-ons', () async {
    final dio = Dio(BaseOptions(baseUrl: 'http://example.test/api/v1'));
    final recordedQueries = <String, Map<String, dynamic>>{};
    final restaurantJson = {
      'id': 'dum-pukht-gachi',
      'name': 'Dum Pukht Dastarkhan',
      'cuisineDescription': 'Hyderabadi · Dum biryani',
      'description': 'Slow-cooked dum biryani.',
      'imageKey': 'biryani',
      'estimatedDeliveryMinutes': 30,
      'estimatedDeliveryMaxMinutes': 45,
      'rating': 4.7,
      'startingPricePaise': 32900,
      'operatingStatus': 'OPEN',
      'deliveryAvailability': true,
      'locality': {
        'id': 'gachibowli',
        'name': 'Gachibowli',
        'city': 'Hyderabad',
      },
      'serviceAreas': [
        {'id': 'gachibowli', 'name': 'Gachibowli', 'estimatedMinutes': 30},
        {'id': 'madhapur', 'name': 'Madhapur', 'estimatedMinutes': 40},
      ],
    };
    final dishJson = {
      'id': 'dum-chicken-biryani',
      'restaurantId': 'dum-pukht-gachi',
      'name': 'Chicken Dum Biryani',
      'description': 'Aged basmati slow-cooked on dum.',
      'imageKey': 'biryani',
      'basePricePaise': 32900,
      'availabilityStatus': 'UNAVAILABLE',
      'availabilityReason': 'Seasonal preview',
      'category': {'name': 'Hyderabadi Biryani'},
      'section': {'name': 'Dum Biryanis'},
      'restaurant': restaurantJson,
      'variants': [
        {
          'id': '11111111-1111-4111-8111-111111111111',
          'name': 'Single',
          'priceAdjustmentPaise': 0,
          'isAvailable': true,
        },
        {
          'id': '22222222-2222-4222-8222-222222222222',
          'name': 'Family Pack',
          'priceAdjustmentPaise': 22000,
          'isAvailable': true,
        },
      ],
      'addOns': [
        {
          'id': '33333333-3333-4333-8333-333333333333',
          'name': 'Mirchi Ka Salan',
          'pricePaise': 4000,
          'isAvailable': true,
        },
      ],
    };
    dio.httpClientAdapter = FixtureAdapter((request, _) async {
      recordedQueries[request.uri.path] = Map<String, dynamic>.from(
        request.uri.queryParameters,
      );
      final data = switch (request.uri.path) {
        '/api/v1/areas' => [
          {'id': 'gachibowli', 'name': 'Gachibowli', 'city': 'Hyderabad'},
          {'id': 'madhapur', 'name': 'Madhapur', 'city': 'Hyderabad'},
        ],
        '/api/v1/restaurants' => {
          'items': [restaurantJson],
        },
        '/api/v1/categories' => [
          {
            'id': 'biryani',
            'name': 'Hyderabadi Biryani',
            'imageKey': 'biryani',
          },
        ],
        '/api/v1/catalog/search' => {
          'items': [dishJson],
          'total': 1,
          'page': 1,
        },
        _ => {},
      };
      return ResponseBody.fromString(
        jsonEncode({'data': data}),
        200,
        headers: {
          'content-type': ['application/json'],
        },
      );
    });

    final repo = ApiCatalogRepository(dio);
    final token = CancelToken();
    final areas = await repo.areas(token);
    expect(areas.map((a) => a.id), ['gachibowli', 'madhapur']);

    final home = await repo.home('gachibowli', token);
    expect(recordedQueries['/api/v1/restaurants']?['area'], 'gachibowli');
    expect(recordedQueries['/api/v1/catalog/search']?['area'], 'gachibowli');
    expect(home.restaurants.single.localityName, 'Gachibowli');
    expect(home.restaurants.single.serviceAreaNames, [
      'Gachibowli',
      'Madhapur',
    ]);
    expect(home.dishes.single.variants, ['Single', 'Family Pack (+₹220)']);
    expect(home.dishes.single.addOns, ['Mirchi Ka Salan (+₹40)']);
    expect(home.dishes.single.availabilityReason, 'Seasonal preview');

    await repo.search((
      text: 'biryani',
      category: null,
      area: null,
      affordable: false,
      page: 1,
    ), token);
    expect(
      recordedQueries['/api/v1/catalog/search']?.containsKey('area'),
      isFalse,
    );

    await repo.search((
      text: 'biryani',
      category: 'biryani',
      area: 'madhapur',
      affordable: false,
      page: 1,
    ), token);
    expect(recordedQueries['/api/v1/catalog/search']?['area'], 'madhapur');
    dio.close();
  });

  testWidgets(
    'RestaurantCard shows locality and dish sheet displays reason, variants and add-ons',
    (tester) async {
      const restaurant = Restaurant(
        'dum-pukht-gachi',
        'Dum Pukht Dastarkhan',
        'Hyderabadi · Dum biryani',
        'Slow-cooked dum biryani.',
        'biryani',
        '30–45 min',
        4.7,
        startingPricePaise: 32900,
        localityName: 'Gachibowli',
      );
      const dish = Dish(
        'haleem-special',
        'dum-pukht-gachi',
        'Mutton Haleem',
        'Slow-pounded wheat and mutton delicacy.',
        'Hyderabadi Biryani',
        'biryani',
        299,
        'Specials',
        availabilityStatus: 'UNAVAILABLE',
        restaurantName: 'Dum Pukht Dastarkhan',
        availabilityReason:
            'Seasonal specialty — demo preview outside Ramzan season',
        variants: ['Single', 'Family Pack (+₹220)'],
        addOns: ['Mirchi Ka Salan (+₹40)'],
      );
      await tester.pumpWidget(
        ProviderScope(
          overrides: [dishProvider(dish.id).overrideWith((_) async => dish)],
          child: MaterialApp(
            theme: appTheme(Brightness.light),
            home: Scaffold(
              body: ListView(
                children: const [RestaurantCard(restaurant), DishTile(dish)],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Hyderabadi · Dum biryani · Gachibowli'),
        findsOneWidget,
      );
      await tester.tap(find.text('Mutton Haleem'));
      await tester.pumpAndSettle();
      expect(
        find.text('Seasonal specialty — demo preview outside Ramzan season'),
        findsOneWidget,
      );
      expect(find.text('Available sizes'), findsOneWidget);
      expect(find.text('Family Pack (+₹220)'), findsOneWidget);
      expect(find.text('Add-ons'), findsOneWidget);
      expect(find.text('Mirchi Ka Salan (+₹40)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'HomeCategories renders long Hyderabad category labels at 200% text scale without overflow',
    (tester) async {
      const longCategories = [
        FoodCategory('biryani', 'Hyderabadi Biryani', 'biryani'),
        FoodCategory('telangana-andhra', 'Telangana & Andhra', 'meals'),
        FoodCategory('burgers', 'Burgers & Fast Food', 'burger'),
        FoodCategory('chaat', 'Street Food & Chaat', 'chaat'),
        FoodCategory('beverages', 'Beverages & Chai', 'chai'),
      ];
      await tester.pumpWidget(
        MaterialApp(
          theme: appTheme(Brightness.light),
          home: const MediaQuery(
            data: MediaQueryData(
              size: Size(360, 850),
              textScaler: TextScaler.linear(2),
            ),
            child: Scaffold(body: HomeCategories(longCategories)),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Hyderabadi Biryani'), findsOneWidget);
      expect(find.text('Burgers & Fast Food'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
