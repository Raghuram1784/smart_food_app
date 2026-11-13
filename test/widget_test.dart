import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
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
        expect(find.text('A little hungry,\nRaghu?'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.scrollUntilVisible(
          find.text('Good things take fire.'),
          500,
          scrollable: find.byType(Scrollable).first,
        );
        await tester.ensureVisible(find.text('Good things take fire.'));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Good things take fire.'));
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
    'Location persists Hyderabad locality and falls back to Madhapur',
    () async {
      SharedPreferences.setMockInitialValues({'locality': 'Indiranagar'});
      final prefs = await SharedPreferences.getInstance();
      var container = ProviderContainer(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
      );
      expect(container.read(locationProvider).id, 'madhapur');
      expect(container.read(locationProvider).name, 'Madhapur');
      await container
          .read(locationProvider.notifier)
          .select(
            ServiceArea.hyderabadAreas.firstWhere((a) => a.id == 'gachibowli'),
          );
      expect(prefs.getString('locality'), 'gachibowli');
      container.dispose();

      container = ProviderContainer(
        overrides: [preferencesProvider.overrideWithValue(prefs)],
      );
      expect(container.read(locationProvider).id, 'gachibowli');
      expect(container.read(locationProvider).name, 'Gachibowli');
      container.dispose();
    },
  );

  testWidgets(
    'Hyderabad locality sheet scrolls cleanly at 360px 200% text scale and updates area',
    (tester) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
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
      expect(
        find.text('YOUR NEIGHBOURHOOD · HYDERABAD · DEMO'),
        findsOneWidget,
      );
      expect(find.text('Madhapur'), findsOneWidget);
      await tester.tap(find.text('Madhapur'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Hyderabad · Demo locations only. No live delivery coverage.',
        ),
        findsOneWidget,
      );
      await tester.scrollUntilVisible(
        find.text('Kukatpally / KPHB'),
        150,
        scrollable: find.byType(Scrollable).last,
      );
      expect(find.text('Kukatpally / KPHB'), findsOneWidget);
      await tester.scrollUntilVisible(
        find.text('Gachibowli'),
        -150,
        scrollable: find.byType(Scrollable).last,
      );
      await tester.ensureVisible(find.text('Gachibowli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gachibowli'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Hyderabad · Demo locations only. No live delivery coverage.',
        ),
        findsNothing,
      );
      expect(find.text('Gachibowli'), findsOneWidget);
      expect(prefs.getString('locality'), 'gachibowli');
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'SearchScreen includes active area filter chip and toggles area query',
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
      expect(recordedAreas, contains('madhapur'));
      await tester.tap(find.text('In Madhapur'));
      await tester.pumpAndSettle();
      expect(recordedAreas.last, isNull);
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
