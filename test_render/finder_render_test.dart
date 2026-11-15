// ignore_for_file: invalid_use_of_visible_for_testing_member
// Render evidence for the Smart Food Finder UI (not part of `flutter test`).
//   flutter test test_render/finder_render_test.dart --update-goldens
// Writes PNGs to test_render/out/. Uses the app's real fonts, icons and food
// photos; the recommendation data is a fixture shaped like the backend response.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

import '../test/auth_test.dart' show FakeAuth, session;
import '../test/finder_test.dart' show FinderFake, rec, results;

Future<void> _fonts() async {
  Future<void> load(String family, List<String> files) async {
    final l = FontLoader(family);
    for (final f in files) {
      l.addFont(Future.value(ByteData.sublistView(File(f).readAsBytesSync())));
    }
    await l.load();
  }

  final flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? 'D:/flutter';
  await load('Sora', ['assets/fonts/Sora.ttf']);
  await load('BricolageGrotesque', ['assets/fonts/BricolageGrotesque.ttf']);
  await load('MaterialIcons', ['$flutterRoot/bin/cache/artifacts/material_fonts/materialicons-regular.otf']);
}

const _n1 = {'servingDescription': '1 half plate', 'servingGrams': 200, 'caloriesKcal': 350, 'proteinG': 17, 'carbsG': 40, 'fatG': 13, 'basis': 'ESTIMATE', 'source': 'Estimate'};
const _n2 = {'servingDescription': '1 plate', 'servingGrams': 300, 'caloriesKcal': 480, 'proteinG': 24, 'carbsG': 60, 'fatG': 15, 'basis': 'ESTIMATE', 'source': 'Estimate'};

Future<void> _render(WidgetTester tester, String file, Json reply, String prompt, {Brightness b = Brightness.light, double scrollBy = 0}) async {
  await _fonts();
  const size = Size(412, 915);
  tester.view.physicalSize = size * 2.625;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final repo = FinderFake()..replies.add((_) => reply);
  final router = GoRouter(routes: [GoRoute(path: '/', builder: (_, _) => const FinderScreen())]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
      commerceRepositoryProvider.overrideWithValue(repo),
      deliveryServiceAreaProvider.overrideWithValue(const ServiceArea('gachibowli', 'Gachibowli', 'Hyderabad')),
    ],
    child: MaterialApp.router(debugShowCheckedModeBanner: false, theme: appTheme(b), routerConfig: router),
  ));
  await tester.pumpAndSettle();
  if (prompt.isNotEmpty) {
    await tester.enterText(find.byKey(const ValueKey('finder-input')), prompt);
    await tester.tap(find.byKey(const ValueKey('finder-send')));
    await tester.pump();
    await tester.pumpAndSettle();
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pumpAndSettle();
    final list = tester.state<ScrollableState>(find.byType(Scrollable).first);
    list.position.jumpTo(scrollBy.clamp(0, list.position.maxScrollExtent));
    await tester.pumpAndSettle();
  }
  // Decode the real food photos before capturing.
  await tester.runAsync(() async {
    for (final e in tester.elementList(find.byType(Image))) {
      await precacheImage((e.widget as Image).image, e);
    }
  });
  await tester.pumpAndSettle();
  await expectLater(find.byType(MaterialApp), matchesGoldenFile('out/$file.png'));
}

void main() {
  testWidgets('welcome', (t) => _render(t, '1_welcome', results(), ''));
  testWidgets('exact match within budget', (t) => _render(t, '2_exact_match', results(
        exact: [rec(nutrition: _n1, total: 14400)],
        near: [rec(id: 'pulao', name: 'Chicken Pulao', food: 12900, total: 16400, status: 'ABOVE_BUDGET', match: 'NEAR_BUDGET', nutrition: _n2)],
      ), 'I want spicy Chicken Biryani under ₹150', scrollBy: 0));
  testWidgets('alternatives and over-budget', (t) => _render(t, '3_alternatives', {
        ...results(
          exact: [],
          similar: [rec(id: 'egg', name: 'Egg Fried Rice', food: 11900, total: 15400, budget: 16000, status: 'WITHIN_BUDGET', match: 'SIMILAR')],
          near: [rec(id: 'mini', name: 'Mini Chicken Dum Biryani', food: 10900, total: 14400, budget: 13000, status: 'ABOVE_BUDGET', match: 'NEAR_BUDGET', nutrition: _n1)],
        ),
        'reply': 'Sorry, I couldn\'t find chicken biryani within your ₹130 total budget. Here is a similar dish that fits, plus 1 option slightly above your budget.',
      }, 'Chicken biryani under ₹130', scrollBy: 260));
  testWidgets('dark mode', (t) => _render(t, '4_dark', results(exact: [rec(nutrition: _n1, total: 15000, status: 'EXACT_BUDGET')], near: []), 'Chicken Biryani for ₹150', b: Brightness.dark));
}
