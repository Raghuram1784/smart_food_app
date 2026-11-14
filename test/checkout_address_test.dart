import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/catalog/catalog_repository.dart';
import 'package:smart_food_demo/features/commerce/cart_screen.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce, addressFixture;

/// FakeCommerce whose address book really changes when the form saves.
class AddressBookCommerce extends FakeCommerce {
  Json? posted;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path == 'addresses' && method == 'POST') {
      calls.add('$method $path');
      posted = data;
      final saved = {...addressFixture(), ...data!, 'id': 'new-address', 'locality': {'name': 'Madhapur'}};
      addresses = [saved];
      return saved;
    }
    return super.request(method, path, data);
  }
}

Future<void> _mountCart(WidgetTester tester, AddressBookCommerce repo) async {
  tester.view.physicalSize = const Size(393, 1400);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => const CartScreen()),
    GoRoute(path: '/addresses', builder: (_, _) => const Scaffold(body: Text('Address manager'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
      commerceRepositoryProvider.overrideWithValue(repo),
      catalogRepositoryProvider.overrideWithValue(OfflineCatalogRepository()),
    ],
    child: MaterialApp.router(routerConfig: router),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('first-time customer: short address form appears only at checkout, saves once, then a summary is shown', (tester) async {
    final repo = AddressBookCommerce()..addresses = [];
    await _mountCart(tester, repo);
    expect(find.text('Add delivery address'), findsOneWidget);
    // Validation blocks an incomplete submission.
    await tester.ensureVisible(find.byKey(const ValueKey('qa-save')));
    await tester.tap(find.byKey(const ValueKey('qa-save')));
    await tester.pumpAndSettle();
    expect(repo.posted, isNull);
    for (final e in {
      'qa-recipient': 'Test Person',
      'qa-phone': '9999999999',
      'qa-house': 'Flat 4B',
      'qa-street': 'Synthetic Towers, Road 2',
      'qa-pincode': '500081',
    }.entries) {
      await tester.enterText(find.byKey(ValueKey(e.key)), e.value);
    }
    await tester.ensureVisible(find.byKey(const ValueKey('qa-area')));
    await tester.tap(find.byKey(const ValueKey('qa-area')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Madhapur').last);
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.byKey(const ValueKey('qa-save')));
    await tester.tap(find.byKey(const ValueKey('qa-save')));
    await tester.pumpAndSettle();
    expect(repo.posted!['addressLine1'], 'Flat 4B, Synthetic Towers, Road 2');
    expect(repo.posted!['localityId'], 'madhapur');
    expect(repo.posted!['latitude'], isNull, reason: 'GPS is optional and not used unless chosen');
    expect(find.text('Add delivery address'), findsNothing);
    expect(find.text('Delivering to Home'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('returning customer: compact summary with Change, no form, no re-entry', (tester) async {
    final repo = AddressBookCommerce();
    await _mountCart(tester, repo);
    expect(find.text('Delivering to Home'), findsOneWidget);
    expect(find.textContaining('100 Test Lane'), findsOneWidget);
    expect(find.text('Add delivery address'), findsNothing);
    expect(find.byKey(const ValueKey('qa-recipient')), findsNothing);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Add new address'), findsOneWidget);
    expect(find.text('Manage saved addresses'), findsOneWidget);
    expect(repo.calls.where((c) => c == 'POST addresses'), isEmpty);
    expect(tester.takeException(), isNull);
  });
}
