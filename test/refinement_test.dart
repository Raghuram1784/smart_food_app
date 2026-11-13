import 'package:smart_food_demo/features/catalog/catalog_repository.dart';

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/discovery/home_screen.dart';
import 'package:smart_food_demo/features/profile/profile_screen.dart';
import 'package:smart_food_demo/features/restaurant/restaurant_screen.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';

void main() {
  test('New Indian catalog preserves original item IDs and prices', () {
    expect(
      dishes
          .where((d) => ['pizza', 'pasta', 'salad', 'burger'].contains(d.id))
          .map((d) => d.price),
      [349, 229, 199, 249],
    );
    for (final id in ['dosa', 'idli', 'biryani', 'paneer']) {
      expect(searchDishes(id, null).any((d) => d.id == id), isTrue);
    }
  });
  test('Semantic text colors meet AA on supporting surfaces', () {
    double contrast(Color a, Color b) {
      final x = a.computeLuminance(), y = b.computeLuminance();
      return (x > y ? x + .05 : y + .05) / (x > y ? y + .05 : x + .05);
    }

    for (final brightness in Brightness.values) {
      final theme = appTheme(brightness), c = theme.colorScheme;
      final accents = theme.extension<CulinaryColors>()!;
      for (final surface in [
        c.surface,
        c.surfaceContainer,
        accents.peach,
        accents.pistachio,
        accents.seaGlass,
        accents.saffron,
      ]) {
        expect(contrast(c.onSurface, surface), greaterThanOrEqualTo(4.5));
      }
      expect(
        contrast(c.onSurfaceVariant, c.surface),
        greaterThanOrEqualTo(4.5),
      );
      expect(contrast(c.primary, c.surface), greaterThanOrEqualTo(4.5));
    }
  });
  Future<void> verifyPhotos(Iterable<String> names) async {
    for (final name in names) {
      for (final folder in ['food', 'categories', 'restaurants']) {
        final bytes = await rootBundle.load('assets/images/$folder/$name.jpg');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0));
        frame.image.dispose();
        codec.dispose();
      }
    }
  }

  testWidgets('Every mapped photo decodes locally', (tester) async {
    await tester.runAsync(() => verifyPhotos(categories.values));
  });
  testWidgets('All 10 new Hyderabad photos decode locally', (tester) async {
    const hyderabadKeys = [
      'chicken-biryani',
      'mutton-biryani',
      'haleem',
      'kebab',
      'noodles',
      'meals',
      'chaat',
      'bakery',
      'chai',
      'dessert',
    ];
    await tester.runAsync(() => verifyPhotos(hyderabadKeys));
  });
  testWidgets('Phase 3.1 specialty food photos decode locally', (tester) async {
    await tester.runAsync(() async {
      for (final name in [
        'karam-dosa',
        'uttapam',
        'vada',
        'dal-curry',
        'roti-naan',
        'cold-beverage',
      ]) {
        final bytes = await rootBundle.load('assets/images/food/$name.jpg');
        final codec = await ui.instantiateImageCodec(
          bytes.buffer.asUint8List(),
        );
        final frame = await codec.getNextFrame();
        expect(frame.image.width, greaterThan(0));
        frame.image.dispose();
        codec.dispose();
      }
    });
  });
  for (final brightness in Brightness.values) {
    testWidgets('360px at 200 percent text scale ${brightness.name}', (
      tester,
    ) async {
      tester.view.physicalSize = const Size(360, 850);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      for (final screen in [
        const HomeScreen(),
        const ProfileScreen(),
        const RestaurantScreen(id: 'tiffin'),
      ]) {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              preferencesProvider.overrideWithValue(prefs),
              catalogRepositoryProvider.overrideWithValue(
                OfflineCatalogRepository(),
              ),
            ],
            child: MaterialApp(
              theme: appTheme(brightness),
              home: MediaQuery(
                data: const MediaQueryData(
                  size: Size(360, 850),
                  textScaler: TextScaler.linear(2),
                ),
                child: Scaffold(body: screen),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        for (var i = 0; i < 8; i++) {
          await tester.drag(
            find.byType(Scrollable).first,
            const Offset(0, -400),
          );
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        }
      }
    });
  }
}
