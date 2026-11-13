import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_widgets.dart';
import 'package:smart_food_demo/features/commerce/cart_screen.dart';
import 'package:smart_food_demo/features/commerce/address_screen.dart';
import 'package:smart_food_demo/features/commerce/orders_screen.dart';

import 'auth_test.dart' show FakeAuth, session;

Json cartFixture() => {
  'id': 'cart',
  'version': 1,
  'restaurantId': 'kitchen',
  'restaurant': {'id': 'kitchen', 'name': 'Test Kitchen'},
  'merchandiseSubtotalPaise': 31000,
  'items': [
    {
      'id': 'line',
      'quantity': 2,
      'unitPricePaise': 15500,
      'lineTotalPaise': 31000,
      'menuItem': {'name': 'Masala dosa', 'imageKey': 'dosa'},
      'variant': {'name': 'Large'},
      'addOns': [
        {
          'addOn': {'name': 'Chutney'},
        },
      ],
    },
  ],
};
Json addressFixture() => {
  'id': 'address',
  'label': 'Home',
  'recipientName': 'Test Customer',
  'contactNumber': '9999999999',
  'addressLine1': '100 Test Lane',
  'addressLine2': '',
  'landmark': '',
  'localityId': 'madhapur',
  'locality': {'name': 'Madhapur'},
  'postalCode': '500081',
  'isDefault': true,
};
Json quoteFixture() => {
  'quoteId': 'quote',
  'cartId': 'cart',
  'cartVersion': 1,
  'restaurant': {'name': 'Test Kitchen'},
  'lines': [
    {
      'name': 'Masala dosa',
      'quantity': 2,
      'variant': {'name': 'Large'},
      'addOns': [
        {'name': 'Chutney'},
      ],
    },
  ],
  'address': {...addressFixture(), 'localityName': 'Madhapur'},
  'basePaise': 24000,
  'variantPaise': 4000,
  'addOnPaise': 1000,
  'packagingPaise': 1000,
  'deliveryPaise': 2000,
  'platformPaise': 500,
  'discountPaise': 0,
  'taxPaise': 0,
  'finalPayablePaise': 32500,
};

class FakeCommerce implements CommerceRepository {
  Json cart = cartFixture();
  List<Json> addresses = [addressFixture()];
  final calls = <String>[];
  Json? pendingInput;
  Completer<Json>? placement;
  Object? failure;
  int placements = 0;
  List<Json> orders = [];
  int pendingCount = 0;
  Object? quoteFailure;
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    calls.add('$method $path');
    if (failure != null) throw failure!;
    if (path == 'cart/quote') {
      if (quoteFailure != null) throw quoteFailure!;
      return quoteFixture();
    }
    if (path == 'cart/items' && method == 'POST') {
      cart['version']++;
      return cart;
    }
    if (path.startsWith('cart/items/') && method == 'PATCH') {
      cart['items'][0]['quantity'] = data!['quantity'];
      cart['version']++;
      return cart;
    }
    if (method == 'DELETE' && path.startsWith('cart')) {
      cart['items'] = [];
      cart['version']++;
      return cart;
    }
    if (path == 'cart') return cart;
    if (path == 'addresses' && method == 'GET') return addresses;
    if (path.startsWith('addresses')) return addressFixture();
    if (path.startsWith('orders?')) {
      return {'items': orders, 'total': orders.length};
    }
    if (path.startsWith('restaurants/')) {
      return {
        'items': orders,
        'total': orders.length,
        'pendingCount': pendingCount,
      };
    }
    if (path.startsWith('orders/')) {
      final id = path.split('/').last;
      return orders.firstWhere((o) => o['id'] == id);
    }
    throw StateError('Unexpected $method $path');
  }

  @override
  Future<Json?> pending(String userId) async => pendingInput;
  @override
  Future<void> forgetPending(String userId) async {
    pendingInput = null;
  }

  @override
  Future<Json> place(String userId, Json input) async {
    placements++;
    pendingInput = input;
    if (failure != null) throw failure!;
    return placement!.future;
  }
}

Future<void> mount(
  WidgetTester tester,
  Widget child,
  FakeCommerce repo, {
  FakeAuth? auth,
  Brightness brightness = Brightness.light,
  double width = 393,
}) async {
  tester.view.physicalSize = Size(width, 900);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final account = auth ?? (FakeAuth()..saved = session());
  addTearDown(account.events.close);
  final router = GoRouter(
    routes: [
      GoRoute(path: '/', builder: (_, _) => child),
      GoRoute(
        path: '/login',
        builder: (_, _) => const Scaffold(body: Text('Login required')),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        authRepositoryProvider.overrideWithValue(account),
        commerceRepositoryProvider.overrideWithValue(repo),
        preferencesProvider.overrideWithValue(prefs),
      ],
      child: MaterialApp.router(
        theme: appTheme(brightness),
        routerConfig: router,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
    'cart restores customizations, badge, quantity, removal and empty state',
    (tester) async {
      final repo = FakeCommerce();
      await mount(
        tester,
        const Stack(
          children: [
            CartScreen(),
            Positioned(top: 0, right: 0, child: CartShortcut()),
          ],
        ),
        repo,
      );
      expect(find.text('Masala dosa'), findsOneWidget);
      expect(find.text('Large'), findsOneWidget);
      expect(find.text('Chutney'), findsOneWidget);
      expect(find.text('₹155 each'), findsOneWidget);
      expect(find.text('₹310'), findsOneWidget);
      await tester.tap(find.byTooltip('Increase Masala dosa'));
      await tester.pumpAndSettle();
      expect(repo.cart['items'][0]['quantity'], 3);
      await tester.tap(find.byTooltip('Decrease Masala dosa'));
      await tester.pumpAndSettle();
      expect(repo.cart['items'][0]['quantity'], 2);
      await tester.tap(find.text('Remove'));
      await tester.pumpAndSettle();
      expect(find.text('Something delicious\nbelongs here.'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    },
  );
  for (final width in [360.0, 393.0, 430.0]) {
    for (final brightness in Brightness.values) {
      testWidgets(
        'cart address, server bill, and no overflow at $width $brightness',
        (tester) async {
          final repo = FakeCommerce();
          await mount(
            tester,
            const CartScreen(),
            repo,
            brightness: brightness,
            width: width,
          );
          await tester.scrollUntilVisible(
            find.text('Bill summary'),
            250,
            scrollable: find.byType(Scrollable).first,
          );
          await tester.pumpAndSettle();
          expect(find.text('₹325'), findsWidgets);
          expect(find.text('₹20'), findsOneWidget);
          expect(find.text('Review order'), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        },
      );
    }
  }
  testWidgets('restaurant switching requires explicit choice before mutation', (
    tester,
  ) async {
    final repo = FakeCommerce();
    await mount(
      tester,
      const Scaffold(
        body: AddToCartButton(
          selection: {
            'restaurantId': 'other',
            'menuItemId': 'meal',
            'area': 'madhapur',
            'quantity': 1,
            'addOnIds': [],
          },
        ),
      ),
      repo,
    );
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    expect(find.text('Start a new cart?'), findsOneWidget);
    await tester.tap(find.text('Keep existing cart'));
    await tester.pumpAndSettle();
    expect(repo.calls.contains('POST cart/items'), false);
    await tester.tap(find.text('Add to cart'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Clear and switch restaurant'));
    await tester.pumpAndSettle();
    expect(repo.calls.contains('POST cart/items'), true);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'signed out add preserves intent until login and does not mutate cart',
    (tester) async {
      final repo = FakeCommerce();
      await mount(
        tester,
        const Scaffold(body: AddToCartButton(selection: {})),
        repo,
        auth: FakeAuth(),
      );
      await tester.tap(find.text('Add to cart'));
      await tester.pumpAndSettle();
      expect(find.text('Login required'), findsOneWidget);
      expect(repo.calls, isEmpty);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'checkout duplicate taps submit once with retained idempotency key',
    (tester) async {
      final repo = FakeCommerce()..placement = Completer<Json>();
      await mount(
        tester,
        CommerceGate(child: CheckoutScreen(quote: quoteFixture())),
        repo,
      );
      await tester.ensureVisible(find.byKey(const ValueKey('place-order')));
      await tester.tap(find.byKey(const ValueKey('place-order')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('place-order')));
      await tester.pump();
      expect(repo.placements, 1);
      expect(repo.pendingInput?['idempotencyKey'], isNotEmpty);
      expect(find.text('Recording order…'), findsOneWidget);
      repo.placement!.completeError(
        DioException(
          requestOptions: RequestOptions(),
          type: DioExceptionType.connectionTimeout,
        ),
      );
      await tester.pumpAndSettle();
      expect(repo.pendingInput, isNotNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets('stale quote requires review before resubmission', (
    tester,
  ) async {
    final repo = FakeCommerce()
      ..failure = DioException(
        requestOptions: RequestOptions(),
        response: Response(
          requestOptions: RequestOptions(),
          statusCode: 409,
          data: {
            'error': {'message': 'Price changed. Review a fresh quote.'},
          },
        ),
      );
    await mount(
      tester,
      CommerceGate(child: CheckoutScreen(quote: quoteFixture())),
      repo,
    );
    await tester.ensureVisible(find.byKey(const ValueKey('place-order')));
    await tester.tap(find.byKey(const ValueKey('place-order')));
    await tester.pumpAndSettle();
    expect(find.text('Price changed. Review a fresh quote.'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(find.byKey(const ValueKey('place-order')))
          .onPressed,
      isNull,
    );
    expect(repo.pendingInput, isNull);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('address form rejects incomplete address and invalid phone', (
    tester,
  ) async {
    final repo = FakeCommerce();
    await mount(tester, const AddressEditor(), repo);
    await tester.ensureVisible(find.text('Save address'));
    await tester.tap(find.text('Save address'));
    await tester.pumpAndSettle();
    expect(repo.calls, isEmpty);
    expect(find.text('Enter a valid Indian mobile number.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('order history and owner inbox show honest empty states', (
    tester,
  ) async {
    final repo = FakeCommerce();
    await mount(tester, const OrdersScreen(), repo);
    expect(find.text('Your first order awaits.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await mount(
      tester,
      const OrdersScreen(restaurantId: 'owned'),
      repo,
      auth: FakeAuth()..saved = session('RESTAURANT_OWNER'),
    );
    expect(find.text('No incoming orders yet.'), findsOneWidget);
    expect(find.textContaining('Open an order to manage'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets('logout immediately hides protected cart', (tester) async {
    final repo = FakeCommerce(), auth = FakeAuth()..saved = session();
    await mount(
      tester,
      const CommerceGate(child: CartScreen()),
      repo,
      auth: auth,
    );
    expect(find.text('Masala dosa'), findsOneWidget);
    auth.events.add(null);
    await tester.pumpAndSettle();
    expect(find.text('Masala dosa'), findsNothing);
    expect(find.text('Sign in to continue.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
  testWidgets(
    'cart prompts address when missing and explains unserviceable quote errors',
    (tester) async {
      final repo = FakeCommerce()..addresses = [];
      await mount(tester, const CartScreen(), repo, width: 360);
      expect(find.text('Choose delivery address'), findsWidgets);
      expect(find.text('Delivery address required'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());

      final blocked = FakeCommerce()
        ..quoteFailure = DioException(
          requestOptions: RequestOptions(),
          response: Response(
            requestOptions: RequestOptions(),
            statusCode: 422,
            data: {
              'error': {'message': 'Kitchen does not serve Secunderabad yet.'},
            },
          ),
        );
      await mount(tester, const CartScreen(), blocked, width: 360);
      await tester.scrollUntilVisible(
        find.text('Checkout unavailable for this address'),
        200,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();
      expect(
        find.text('Kitchen does not serve Secunderabad yet.'),
        findsOneWidget,
      );
      expect(find.text('Change address'), findsWidgets);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
  testWidgets(
    'confirmation, customer history/detail, and dark owner inbox/detail render cleanly at 360px',
    (tester) async {
      final sampleOrder = <String, dynamic>{
        'id': 'ord-1',
        'orderNumber': 'FD-AA98F142DE6365012887',
        'restaurantId': 'deccan-handi-gachi',
        'restaurantName': 'Deccan Handi & Dum Kitchen Long Title',
        'status': 'PENDING_RESTAURANT',
        'paymentStatus': 'UNPAID',
        'createdAt': '2026-11-12T15:43:52.000Z',
        'itemSubtotalPaise': 108700,
        'customizationTotalPaise': 7000,
        'packagingPaise': 1000,
        'deliveryPaise': 2000,
        'platformPaise': 500,
        'discountPaise': 0,
        'taxPaise': 0,
        'finalPayablePaise': 119200,
        'deliveryAddressSnapshot': {
          ...addressFixture(),
          'localityName': 'Madhapur',
        },
        'items': [
          {
            'name': 'Chicken Dum Biryani Special Hyderabadi Pack',
            'imageKey': 'biryani',
            'quantity': 2,
            'lineTotalPaise': 72800,
            'variantSnapshot': {'name': 'Single'},
            'addOns': [
              {'name': 'Caramelised Onions (Birista)'},
            ],
          },
          {
            'name': 'Mutton Zafrani Dum Biryani',
            'imageKey': 'mutton-biryani',
            'quantity': 1,
            'lineTotalPaise': 42900,
            'variantSnapshot': {'name': 'Single'},
            'addOns': <Map<String, dynamic>>[],
          },
        ],
      };

      final repo = FakeCommerce()
        ..orders = [sampleOrder]
        ..pendingCount = 1;

      await mount(
        tester,
        const OrderDetailScreen(id: 'ord-1', placed: true),
        repo,
        width: 360,
      );
      expect(find.text('Your order has been recorded'), findsOneWidget);
      expect(find.text('FD-AA98…2887'), findsOneWidget);
      expect(find.text('Awaiting restaurant action'), findsOneWidget);
      expect(find.text('No real payment collected'), findsOneWidget);
      expect(find.text('View order details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      await mount(tester, const OrdersScreen(), repo, width: 360);
      expect(find.textContaining('FD-AA98…2887'), findsOneWidget);
      expect(find.text('₹1192'), findsOneWidget);
      expect(find.text('View details'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      await mount(
        tester,
        const OrdersScreen(restaurantId: 'deccan-handi-gachi'),
        repo,
        auth: FakeAuth()..saved = session('RESTAURANT_OWNER'),
        brightness: Brightness.dark,
        width: 360,
      );
      expect(find.text('1 pending'), findsOneWidget);
      expect(find.text('FD-AA98…2887'), findsOneWidget);
      expect(find.text('Accept order'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      final ownerOrder = Map<String, dynamic>.from(sampleOrder)
        ..remove('deliveryAddressSnapshot');
      final ownerRepo = FakeCommerce()..orders = [ownerOrder];
      await mount(
        tester,
        OwnerOrderDetailScreen(
          restaurantId: 'deccan-handi-gachi',
          orderId: 'ord-1',
          initialOrder: ownerOrder,
        ),
        ownerRepo,
        auth: FakeAuth()..saved = session('RESTAURANT_OWNER'),
        brightness: Brightness.dark,
        width: 360,
      );
      expect(find.text('FD-AA98F142DE6365012887'), findsOneWidget);
      expect(find.text('Option: Single'), findsWidgets);
      expect(
        find.text('Add-ons: Caramelised Onions (Birista)'),
        findsOneWidget,
      );
      expect(find.text('Delivery address'), findsNothing);
      expect(find.text('Accept order'), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    },
  );
}
