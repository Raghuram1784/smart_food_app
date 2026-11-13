import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/features/catalog/catalog.dart';
import 'package:smart_food_demo/main.dart' as app;

Future<void> waitFor(WidgetTester tester, Finder finder) async {
  for (var i = 0; i < 200; i++) {
    await tester.pump(const Duration(milliseconds: 100));
    if (finder.evaluate().isNotEmpty) {
      await tester.pumpAndSettle();
      return;
    }
  }
  expect(finder, findsWidgets);
}

Future<void> visibleTap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'Madhapur live payable budget, customization, comparison and themes',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('locality', 'madhapur');
      await prefs.setString('appearance', 'light');
      await app.main();
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('Madhapur'));
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      await waitFor(tester, find.byKey(const ValueKey('smart-search-input')));
      await tester.enterText(
        find.byKey(const ValueKey('smart-search-input')),
        'masala dosa',
      );
      await tester.pump(const Duration(milliseconds: 400));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Meal filters'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byKey(const ValueKey('budget-input')), '150');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('Vegetarian only'));
      await visibleTap(tester, find.text('Within 30 minutes'));
      await visibleTap(tester, find.text('Show matching meals'));
      await waitFor(tester, find.text('No matches within ₹150.'));
      await waitFor(tester, find.text('Increase budget to ₹184'));
      await tester.ensureVisible(find.text('No matches within ₹150.'));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pump();
      await binding.takeScreenshot('01-madhapur-150-honest-empty');

      // Relax actual constraints via filter sheet; never invent a result when the 150/30-minute request is empty.
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1800));
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byTooltip('Meal filters'));
      await tester.enterText(find.byKey(const ValueKey('budget-input')), '250');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('Within 45 minutes'));
      await visibleTap(tester, find.text('Show matching meals'));
      await waitFor(tester, find.text('3 meals in Madhapur'));
      await visibleTap(tester, find.text('Best value'));
      await tester.tap(find.text('Lowest payable').last);
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('Lowest payable'));
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('quote-gtc-ghee-masala-dosa')),
        250,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('paise'), findsNothing);
      expect(find.textContaining('Value score'), findsNothing);
      await binding.takeScreenshot('02-eligible-server-priced-meals');
      await visibleTap(
        tester,
        find.byKey(const ValueKey('quote-gtc-ghee-masala-dosa')),
      );
      await waitFor(tester, find.text('Available sizes'));
      final dio = Dio(
        BaseOptions(
          baseUrl: 'http://10.0.2.2:5000/api/v1/',
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 10),
        ),
      );
      final detail = (await dio.get('menu-items/gtc-ghee-masala-dosa'))
          .data['data'];
      final variants = (detail['variants'] as List)
          .where((v) => v['isAvailable'] == true)
          .toList();
      final addons = (detail['addOns'] as List)
          .where((v) => v['isAvailable'] == true)
          .toList();
      final variant = variants.last, addon = addons.first;
      await visibleTap(
        tester,
        find.text(
          '${variant['name']} · +₹${formatPaise(variant['priceAdjustmentPaise'])}',
        ),
      );
      await visibleTap(
        tester,
        find.text('${addon['name']} · +₹${formatPaise(addon['pricePaise'])}'),
      );
      final expected = (await dio.post(
        'pricing/quote',
        data: {
          'restaurantId': detail['restaurantId'],
          'menuItemId': detail['id'],
          'area': 'madhapur',
          'variantId': variant['id'],
          'addOnIds': [addon['id']],
          'quantity': 1,
        },
      )).data['data'];
      await waitFor(
        tester,
        find.text('₹${formatPaise(expected['finalPayablePaise'])}'),
      );
      expect(find.textContaining('DEMO_'), findsNothing);
      await tester.ensureVisible(find.text('Final payable'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('03-customized-live-quote');
      await visibleTap(tester, find.text('Quote & fee details'));
      await waitFor(tester, find.textContaining('DEMO_PACKAGING_V1'));
      await visibleTap(tester, find.text('Back to exploring'));

      await visibleTap(
        tester,
        find.byKey(const ValueKey('compare-gtc-ghee-masala-dosa')),
      );
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1800));
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('compare-dosa')),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await visibleTap(tester, find.byKey(const ValueKey('compare-dosa')));
      await tester.tap(find.text('Compare 2 meals'));
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('Compare meals'));
      await waitFor(tester, find.text('Final payable').first);
      await binding.takeScreenshot('04-live-comparison');
      await visibleTap(tester, find.text('Back to meals'));

      await tester.drag(find.byType(Scrollable).first, const Offset(0, 2400));
      await tester.pumpAndSettle();
      await visibleTap(tester, find.text('Reset filters'));
      await tester.enterText(
        find.byKey(const ValueKey('smart-search-input')),
        'haleem',
      );
      await tester.pump(const Duration(milliseconds: 400));
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('Seasonal or currently unavailable'));
      await waitFor(tester, find.text('Old City Mutton Haleem'));
      final unavailable = await dio.post(
        'pricing/quote',
        data: {
          'restaurantId': 'deccan-handi-gachi',
          'menuItemId': 'dhd-shahi-haleem',
          'area': 'madhapur',
          'quantity': 1,
          'addOnIds': [],
        },
        options: Options(validateStatus: (_) => true),
      );
      expect(unavailable.statusCode, 422);
      await tester.ensureVisible(find.text('Old City Mutton Haleem'));
      await tester.pumpAndSettle();
      await binding.takeScreenshot('05-seasonal-not-orderable');
      await visibleTap(tester, find.text('Old City Mutton Haleem'));
      await waitFor(
        tester,
        find.textContaining('live quotes and ordering are disabled'),
      );
      expect(find.text('Customize meal'), findsNothing);
      await visibleTap(tester, find.text('Back to exploring'));
      await tester.drag(find.byType(Scrollable).first, const Offset(0, 1800));
      await tester.pumpAndSettle();
      await visibleTap(tester, find.byTooltip('Clear search'));
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Dark mode'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Explore'));
      await tester.pumpAndSettle();
      await waitFor(tester, find.text('View meal & quote'));
      await binding.takeScreenshot('06-smart-discovery-dark');
      await tester.scrollUntilVisible(
        find.textContaining('Show more meals'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await visibleTap(tester, find.textContaining('Show more meals'));
      for (
        var i = 0;
        i < 80 && find.byType(CircularProgressIndicator).evaluate().isNotEmpty;
        i++
      ) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      await tester.pumpAndSettle();
      await tester.scrollUntilVisible(
        find.textContaining('Showing 24 of'),
        350,
        scrollable: find.byType(Scrollable).first,
      );
      expect(find.textContaining('Showing 24 of'), findsOneWidget);
      await tester.tap(find.text('You'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Light mode'));
      await tester.pumpAndSettle();
      dio.close();
      expect(tester.takeException(), isNull);
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
