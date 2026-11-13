import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:smart_food_demo/main.dart' as app;

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets('PostgreSQL → API → Android, refresh, restore and themes', (
    tester,
  ) async {
    await app.main();
    await tester.pumpAndSettle();
    expect(find.text('Live catalog · sample data'), findsOneWidget);
    expect(find.text('A little hungry,\nRaghu?'), findsOneWidget);
    await binding.convertFlutterSurfaceToImage();
    await tester.pump();
    await binding.takeScreenshot('01-live-home');
    await tester.scrollUntilVisible(
      find.textContaining('The Tiffin Room ·'),
      250,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.textContaining('The Tiffin Room ·'));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Masala dosa'), 200);
    await tester.ensureVisible(find.text('Masala dosa'));
    await tester.tap(find.text('Masala dosa'));
    await tester.pumpAndSettle();
    expect(find.text('₹149'), findsOneWidget);
    await binding.takeScreenshot('02-dosa-original');
    await tester.ensureVisible(find.text('Back to exploring'));
    await tester.tap(find.text('Back to exploring'));
    await tester.pumpAndSettle();
    // A host-side operator changes only the dedicated development record.
    // No database credentials or write API exist in the Android application.
    debugPrint('PHASE2_READY_FOR_CHANGE');
    final dio = Dio(
      BaseOptions(
        connectTimeout: const Duration(seconds: 5),
        receiveTimeout: const Duration(seconds: 5),
      ),
    );
    Future<void> waitForPrice(int paise) async {
      for (var attempt = 0; attempt < 120; attempt++) {
        final result = await dio.get(
          'http://10.0.2.2:5000/api/v1/menu-items/dosa',
        );
        if (result.data['data']['basePricePaise'] == paise) return;
        await Future<void>.delayed(const Duration(seconds: 1));
      }
      fail('The host-side database change was not observed');
    }

    await waitForPrice(14937);
    // Pull down from the top of the menu to trigger its actual refresh action.
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 1600));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(CustomScrollView), const Offset(0, 450));
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(find.text('Masala dosa'), 200);
    expect(find.text('₹149.37 · sample'), findsOneWidget);
    await tester.tap(find.text('Masala dosa'));
    await tester.pumpAndSettle();
    expect(find.text('₹149.37'), findsOneWidget);
    await binding.takeScreenshot('03-dosa-database-change');
    debugPrint('PHASE2_READY_FOR_RESTORE');
    await waitForPrice(14900);
    await tester.ensureVisible(find.text('Back to exploring'));
    await tester.tap(find.text('Back to exploring'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Masala dosa'));
    await tester.pumpAndSettle();
    expect(find.text('₹149'), findsOneWidget);
    await binding.takeScreenshot('04-dosa-restored');
    await tester.ensureVisible(find.text('Back to exploring'));
    await tester.tap(find.text('Back to exploring'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('You'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Dark mode'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('05-live-dark-profile');
    await tester.tap(find.text('Light mode'));
    await tester.pumpAndSettle();
    await binding.takeScreenshot('06-live-light-profile');
    dio.close();
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(minutes: 6)));
}
