import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/main.dart' as app;

Future<void> _waitForFinder(
  WidgetTester tester,
  Finder finder, {
  Duration timeout = const Duration(seconds: 15),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  await tester.pumpAndSettle();
  expect(finder, findsWidgets);
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Phase 2.5 Hyderabad marketplace: areas, menu variants/add-ons, Haleem search & dark mode',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('locality');
      await prefs.remove('appearance');

      await app.main();
      await tester.pumpAndSettle();
      await _waitForFinder(tester, find.text('Live catalog · sample data'));
      expect(find.text('Live catalog · sample data'), findsOneWidget);
      expect(find.text('Madhapur'), findsOneWidget);

      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('01-hyd-home-madhapur-light');

      await tester.tap(find.text('Madhapur'));
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Hyderabad · Demo locations only. No live delivery coverage.',
        ),
        findsOneWidget,
      );
      await binding.takeScreenshot('02-hyd-locality-picker');

      await tester.ensureVisible(find.text('Gachibowli'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Gachibowli'));
      await tester.pumpAndSettle();

      await _waitForFinder(tester, find.text('Gachibowli'));
      await _waitForFinder(tester, find.text('A little hungry,\nRaghu?'));
      await tester.scrollUntilVisible(
        find.text('Deccan Handi & Dum'),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Deccan Handi & Dum'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03-hyd-home-gachibowli');

      await tester.tap(find.text('Deccan Handi & Dum'));
      await tester.pumpAndSettle();
      await _waitForFinder(tester, find.text('Signature Dum Biryanis'));
      await binding.takeScreenshot('04-hyd-restaurant-menu');

      await tester.scrollUntilVisible(
        find.text('Chicken Dum Biryani'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Chicken Dum Biryani'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Chicken Dum Biryani'));
      await tester.pumpAndSettle();
      await _waitForFinder(tester, find.text('Available sizes'));
      expect(find.text('Available sizes'), findsOneWidget);
      expect(find.text('Add-ons'), findsOneWidget);
      await binding.takeScreenshot('05-hyd-dish-variants-addons');

      await tester.ensureVisible(find.text('Back to exploring'));
      await tester.tap(find.text('Back to exploring'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark mode'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'haleem');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      await _waitForFinder(tester, find.text('10 dishes · page 1'));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.text('Old City Mutton Haleem'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.ensureVisible(find.text('Old City Mutton Haleem'));
      await tester.pumpAndSettle();
      expect(find.text('unavailable'), findsWidgets);
      await binding.takeScreenshot('06-hyd-search-haleem-dark');

      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light mode'));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 6)),
  );
}
