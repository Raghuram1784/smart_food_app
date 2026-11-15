import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/location/delivery_destination.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';

void main() {
  test(
    'Search matches dishes, restaurants and cuisine with intersecting filters',
    () {
      expect(searchDishes('  ITALIAN ', null).length, 2);
      expect(
        searchDishes('green table', null).map((d) => d.id),
        contains('salad'),
      );
      expect(searchDishes('tomato basil', 'Pasta').single.id, 'pasta');
      expect(searchDishes('pizza', 'Bowls'), isEmpty);
      expect(
        searchDishes('', null, affordable: true).map((d) => d.price),
        everyElement(lessThanOrEqualTo(250)),
      );
      expect(searchDishes('unknown', null), isEmpty);
      for (final d in dishes) {
        expect(restaurants.any((r) => r.id == d.restaurantId), isTrue);
      }
    },
  );
  test(
    'Appearance survives provider restart and invalid settings fall back',
    () async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      var container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          catalogRepositoryProvider.overrideWithValue(
            OfflineCatalogRepository(),
          ),
        ],
      );
      expect(container.read(appearanceProvider), ThemeMode.system);
      expect(
        await container
            .read(appearanceProvider.notifier)
            .select(ThemeMode.dark),
        isTrue,
      );
      container.dispose();
      container = ProviderContainer(
        overrides: [
          preferencesProvider.overrideWithValue(prefs),
          catalogRepositoryProvider.overrideWithValue(
            OfflineCatalogRepository(),
          ),
        ],
      );
      expect(container.read(appearanceProvider), ThemeMode.dark);
      container.dispose();
    },
  );
  for (final width in [360.0, 393.0, 430.0]) {
    for (final mode in ThemeMode.values) {
      testWidgets('Navigation and layouts at $width in ${mode.name}', (
        tester,
      ) async {
        tester.view.physicalSize = Size(width, 850);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        SharedPreferences.setMockInitialValues({'appearance': mode.name});
        final prefs = await SharedPreferences.getInstance();
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider.overrideWithValue(prefs),
              catalogRepositoryProvider.overrideWithValue(
                OfflineCatalogRepository(),
              ),
              authRepositoryProvider.overrideWithValue(_FakeAuthRepository()),
            ],
            child: const FoodApp(),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byKey(const ValueKey('home-search')), findsOneWidget);
        expect(tester.takeException(), isNull);
        // Redesigned Home: open a kitchen from the "Restaurants in your area" row.
        await tester.scrollUntilVisible(
          find.byKey(const ValueKey('home-restaurants')),
          300,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('home-restaurants'));
        await tester.dragUntilVisible(
          find.descendant(of: row, matching: find.text('Hearth & Crust')),
          row,
          const Offset(-200, 0),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.descendant(of: row, matching: find.text('Hearth & Crust')));
        await tester.pumpAndSettle();
        expect(find.text('Hearth & Crust'), findsWidgets);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(find.text('Wood-fired pepperoni'), 250);
        await tester.ensureVisible(find.text('Wood-fired pepperoni'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Wood-fired pepperoni'));
        await tester.pumpAndSettle();
        expect(find.text('Back to exploring'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.tap(find.text('Back to exploring'));
        await tester.pumpAndSettle();
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Search'));
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'nonsense');
        await tester.pump(const Duration(milliseconds: 350));
        await tester.pumpAndSettle();
        expect(find.text('Reset search'), findsOneWidget);
        await tester.ensureVisible(find.text('Reset search'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Reset search'));
        await tester.pumpAndSettle();
        await tester.ensureVisible(find.text('Pasta'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Pasta'));
        await tester.pumpAndSettle();
        expect(find.text('Tomato & basil penne'), findsOneWidget);
        expect(find.text('Signature cheeseburger'), findsNothing);
        await tester.tap(find.text('Account'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Dark mode'));
        await tester.pumpAndSettle();
        expect(prefs.getString('appearance'), 'dark');
        expect(tester.takeException(), isNull);
      });
    }
  }

  test(
    'Delivery destination: no demo default, persists the selected saved address per customer',
    () async {
      SharedPreferences.setMockInitialValues({'locality': 'madhapur'});
      final prefs = await SharedPreferences.getInstance();
      final home = {'id': 'a-home', 'label': 'Home', 'addressLine1': '1 Lane', 'localityId': 'gachibowli', 'locality': {'name': 'Gachibowli'}, 'city': 'Hyderabad', 'isDefault': false, 'hasConfirmedLocation': true, 'latitude': 17.4, 'longitude': 78.3};
      final family = {'id': 'a-family', 'label': 'Family', 'addressLine1': '2 Lane', 'localityId': null, 'city': 'Hyderabad', 'isDefault': false, 'hasConfirmedLocation': true, 'latitude': 17.5, 'longitude': 78.4};
      ProviderContainer make(String? customer, List<Map<String, dynamic>> addresses) => ProviderContainer(
            overrides: [
              preferencesProvider.overrideWithValue(prefs),
              customerIdProvider.overrideWithValue(customer),
              addressesProvider.overrideWith((ref) async => addresses),
            ],
          );
      var c = make('cust-1', [home, family]);
      await c.read(addressesProvider.future);
      // A legacy "locality" preference is ignored; nothing selected and no default -> no destination.
      expect(c.read(deliveryDestinationProvider).value, isNull);
      expect(c.read(deliveryServiceAreaProvider), isNull);
      await c.read(selectedAddressIdProvider.notifier).select('a-home');
      expect(c.read(deliveryDestinationProvider).value?['id'], 'a-home');
      expect(c.read(deliveryServiceAreaProvider)?.id, 'gachibowli');
      expect(prefs.getString('delivery_address_cust-1'), 'a-home');
      await c.read(selectedAddressIdProvider.notifier).select('a-family');
      expect(c.read(deliveryServiceAreaProvider), isNull, reason: 'outside service areas has no pricing area');
      c.dispose();

      // Restart: restored for the same customer, not leaked to another customer.
      c = make('cust-1', [home, family]);
      await c.read(addressesProvider.future);
      expect(c.read(deliveryDestinationProvider).value?['id'], 'a-family');
      c.dispose();
      c = make('cust-2', [{...home, 'id': 'b-1', 'isDefault': true}]);
      await c.read(addressesProvider.future);
      expect(c.read(deliveryDestinationProvider).value?['id'], 'b-1', reason: 'falls back to the default saved address');
      c.dispose();
      // Signed out: no destination.
      c = make(null, []);
      expect(c.read(deliveryDestinationProvider).value, isNull);
      c.dispose();
    },
  );

  testWidgets(
    'Home shows a Deliver-to selector with no hardcoded locality at 360px 200% text scale',
    (tester) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({'locality': 'madhapur'});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            catalogRepositoryProvider.overrideWithValue(
              OfflineCatalogRepository(),
            ),
          ],
          child: MediaQuery(
            data: const MediaQueryData(
              size: Size(360, 850),
              textScaler: TextScaler.linear(2),
            ),
            child: const FoodApp(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('DELIVER TO'), findsOneWidget);
      expect(find.text('Sign in to set a delivery location'), findsOneWidget);
      expect(find.text('YOUR NEIGHBOURHOOD · HYDERABAD · DEMO'), findsNothing);
      expect(find.text('Madhapur'), findsNothing);
      expect(find.textContaining('Raghu'), findsNothing);
      expect(find.textContaining('Ordering is not yet available'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SearchScreen is not scoped to a demo locality without a confirmed destination',
    (tester) async {
      final recordedAreas = <String?>[];
      final repo = _RecordingCatalogRepository(recordedAreas);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            preferencesProvider.overrideWithValue(prefs),
            catalogRepositoryProvider.overrideWithValue(repo),
          ],
          child: const FoodApp(),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Search'));
      await tester.pumpAndSettle();
      // No confirmed destination: search is not silently scoped to a demo locality.
      expect(recordedAreas, isNotEmpty);
      expect(recordedAreas.every((a) => a == null), isTrue);
      expect(find.textContaining('In Madhapur'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}

class _RecordingCatalogRepository extends OfflineCatalogRepository {
  final List<String?> recordedAreas;
  _RecordingCatalogRepository(this.recordedAreas);

  @override
  Future<CatalogPage> search(SearchQuery query, CancelToken token) {
    recordedAreas.add(query.area);
    return super.search(query, token);
  }
}

class _FakeAuthRepository implements AuthRepository {
  final events = StreamController<void>.broadcast(sync: true);
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<AuthSession?> restore() async => null;
  @override
  Future<AuthSession> login(String email, String password) =>
      throw UnimplementedError();
  @override
  Future<void> logout({bool all = false}) async {}
  @override
  Future<void> expire() async {}
  @override
  Future<AuthSession> updateName(String name) => throw UnimplementedError();
  @override
  Future<Map<String, dynamic>> context(String path) =>
      throw UnimplementedError();
}
