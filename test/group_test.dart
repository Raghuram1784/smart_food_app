import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/core/design.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/commerce_repository.dart';
import 'package:smart_food_demo/features/group/group_screens.dart';
import 'package:smart_food_demo/features/group/owner_group_proposals_screen.dart';

import 'auth_test.dart' show FakeAuth, session;
import 'commerce_test.dart' show FakeCommerce;

const gid = '11111111-1111-4111-8111-111111111111';
const pid = '22222222-2222-4222-8222-222222222222';

Json groupFixture({String status = 'OPEN', bool organizer = true, Json? proposal}) => {
      'id': gid, 'name': 'Friday lunch', 'status': status, 'version': 7, 'cartRevision': 4, 'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(), 'orderId': status == 'ORDERED' ? 'order-1' : null,
      'restaurant': {'id': 'deccan-handi-kphb', 'name': 'Deccan Handi & Dum', 'imageKey': 'biryani', 'locality': 'Kukatpally / KPHB, Hyderabad', 'open': true, 'negotiationEnabled': true},
      'organizerId': 'u-a', 'isOrganizer': organizer,
      'members': [
        {'userId': 'u-a', 'name': 'Asha', 'isOrganizer': true, 'isYou': organizer},
        {'userId': 'u-b', 'name': 'Bala', 'isOrganizer': false, 'isYou': !organizer},
      ],
      'items': [
        {'id': 'i-1', 'memberId': 'u-a', 'memberName': 'Asha', 'mine': organizer, 'menuItemId': 'm1', 'name': 'Chicken Dum Biryani with an unusually long descriptive name', 'imageKey': 'biryani', 'isVegetarian': false, 'available': true, 'quantity': 2, 'version': 1, 'variant': null, 'addOns': [], 'lineTotalPaise': 37800, 'sharedWith': ['u-a', 'u-b'], 'sharedWithNames': ['Asha', 'Bala'], 'canShare': organizer},
        {'id': 'i-2', 'memberId': 'u-b', 'memberName': 'Bala', 'mine': !organizer, 'menuItemId': 'm2', 'name': 'Veg Dum Biryani', 'imageKey': 'biryani', 'isVegetarian': true, 'available': true, 'quantity': 1, 'version': 1, 'variant': null, 'addOns': [], 'lineTotalPaise': 15900, 'sharedWith': [], 'sharedWithNames': [], 'canShare': true},
      ],
      'contributions': [
        {'userId': 'u-a', 'name': 'Asha', 'itemCount': 2, 'itemTotalPaise': 37800},
        {'userId': 'u-b', 'name': 'Bala', 'itemCount': 1, 'itemTotalPaise': 15900},
      ],
      'pricing': {'itemSubtotalPaise': 53700, 'customizationTotalPaise': 0, 'packagingPaise': 1000, 'deliveryPaise': 2000, 'platformPaise': 500, 'discountPaise': 0, 'taxPaise': 0, 'normalTotalPaise': 57200},
      'pricingError': null, 'memberCount': 2, 'proposal': proposal, 'proposalAttempts': proposal == null ? 0 : 1, 'maxProposals': 5,
      'negotiationRange': {'maxDiscountBps': 3000, 'minAllowedTotalPaise': 40040},
      'permissions': {
        'canEditOwnItems': status == 'OPEN', 'canLock': organizer && status == 'OPEN', 'canUnlock': organizer && ['LOCKED', 'REJECTED'].contains(status),
        'canPropose': organizer && ['LOCKED', 'REJECTED'].contains(status), 'canRespondToCounter': organizer && status == 'COUNTERED', 'canCheckout': organizer && status == 'ACCEPTED',
        'canLeave': !organizer && ['OPEN', 'LOCKED'].contains(status), 'canCancel': organizer && !['ORDERED', 'CANCELED', 'EXPIRED'].contains(status), 'canInvite': organizer && status == 'OPEN',
      },
      'paymentNote': 'The organizer pays the final order total. Individual amounts are for information only.',
      'split': {
        'method': 'BY_PERSON', 'basis': 'ESTIMATE', 'organizerId': 'u-a', 'payablePaise': 57200, 'sumPaise': 57200, 'note': 'Estimate from the normal price.',
        'members': [
          {'userId': 'u-a', 'name': 'Asha', 'foodPaise': 18900, 'feesPaise': 1235, 'discountPaise': 0, 'sharePaise': 20135, 'items': [{'name': 'Chicken Dum Biryani', 'portionPaise': 18900, 'sharedBetween': 2}]},
          {'userId': 'u-b', 'name': 'Bala', 'foodPaise': 34800, 'feesPaise': 2265, 'discountPaise': 0, 'sharePaise': 37065, 'items': [{'name': 'Chicken Dum Biryani', 'portionPaise': 18900, 'sharedBetween': 2}, {'name': 'Veg Dum Biryani', 'portionPaise': 15900, 'sharedBetween': 1}]},
        ],
      },
    };

Json proposalFixture(String status, {int? counter, int? agreed}) => {
      'id': pid, 'restaurantId': 'deccan-handi-kphb', 'status': status, 'cartRevision': 4, 'normalTotalPaise': 57200, 'proposedTotalPaise': 46000, 'requestedReductionPaise': 11200,
      'counterTotalPaise': counter, 'agreedTotalPaise': agreed, 'minAllowedTotalPaise': 40040,
      'responseExpiresAt': DateTime.now().add(const Duration(minutes: 14)).toIso8601String(), 'offerExpiresAt': DateTime.now().add(const Duration(minutes: 29)).toIso8601String(), 'responseNote': null,
    };

class GroupFake extends FakeCommerce {
  Json group;
  final posts = <String, Json?>{};
  List<Json> proposals = [];
  GroupFake(this.group);
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    if (path.startsWith('groups') || path.startsWith('restaurant/group-proposals')) {
      calls.add('$method $path');
      if (method != 'GET') posts['$method $path'] = data;
      if (path.endsWith('/checkout')) return {'orderId': 'order-1', 'finalPayablePaise': 49000};
      if (path == 'groups/join') return group;
      if (path.startsWith('restaurant/group-proposals') && method == 'GET') return proposals;
      if (path.startsWith('restaurant/group-proposals')) return proposals.first;
      if (path == 'groups' && method == 'GET') return [];
      return group;
    }
    return super.request(method, path, data);
  }
}

Future<GoRouter> _mount(WidgetTester tester, GroupFake repo, Widget home, {Size size = const Size(393, 1400), double text = 1}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  SharedPreferences.setMockInitialValues({});
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(routes: [
    GoRoute(path: '/', builder: (_, _) => home),
    GoRoute(path: '/orders/:id', builder: (_, s) => Scaffold(body: Text('Order ${s.pathParameters['id']}'))),
    GoRoute(path: '/groups/:id', builder: (_, s) => Scaffold(body: Text('Room ${s.pathParameters['id']}'))),
  ]);
  addTearDown(router.dispose);
  await tester.pumpWidget(ProviderScope(
    overrides: [
      preferencesProvider.overrideWithValue(prefs),
      authRepositoryProvider.overrideWithValue(FakeAuth()..saved = session()),
      commerceRepositoryProvider.overrideWithValue(repo),
    ],
    child: MediaQuery(data: MediaQueryData(size: size, textScaler: TextScaler.linear(text)), child: MaterialApp.router(theme: appTheme(Brightness.light), routerConfig: router)),
  ));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 50));
  return router;
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  testWidgets('group room (organizer, OPEN): members, shared cart, own-item controls, lock; no overflow at 360px / 150%', (tester) async {
    final repo = GroupFake(groupFixture());
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid), size: const Size(360, 1600), text: 1.5);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('Asha'), findsWidgets);
    expect(find.text('Bala'), findsWidgets);
    expect(find.textContaining('organizer pays the final order total'), findsOneWidget);
    expect(find.text('₹572'), findsOneWidget, reason: 'normal total from the server');
    expect(find.byTooltip('More'), findsOneWidget, reason: 'controls only on my own item');
    await tester.ensureVisible(find.byKey(const ValueKey('group-lock')));
    await tester.tap(find.byKey(const ValueKey('group-lock')));
    await _settle(tester);
    expect(repo.posts['POST groups/$gid/lock'], {'expectedVersion': 7});
  });

  testWidgets('member view: cannot edit others, cannot lock, can leave', (tester) async {
    final repo = GroupFake(groupFixture(organizer: false));
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid));
    await _settle(tester);
    expect(find.byKey(const ValueKey('group-lock')), findsNothing);
    expect(find.byTooltip('More'), findsOneWidget, reason: 'only Bala\'s own line is editable');
    expect(find.text('Leave group'), findsOneWidget);
  });

  testWidgets('waiting, counteroffer (accept), accepted (checkout) and rejected (alternatives) states', (tester) async {
    final repo = GroupFake(groupFixture(status: 'PROPOSED', proposal: proposalFixture('PENDING')));
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid));
    await _settle(tester);
    expect(find.text('Price request sent'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-waiting')), findsOneWidget);

    repo.group = groupFixture(status: 'COUNTERED', proposal: proposalFixture('COUNTERED', counter: 51000));
    await tester.tap(find.byTooltip('Refresh'));
    await _settle(tester);
    expect(find.text('Restaurant offered ₹510'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('group-accept-counter')));
    await _settle(tester);
    expect(repo.posts['POST groups/$gid/proposals/$pid/counter'], {'answer': 'accept', 'expectedVersion': 7});

    repo.group = groupFixture(status: 'ACCEPTED', proposal: proposalFixture('ACCEPTED', counter: 51000, agreed: 51000));
    await tester.tap(find.byTooltip('Refresh'));
    await _settle(tester);
    expect(find.text('Restaurant accepted ₹510'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('group-checkout')));
    await tester.tap(find.byKey(const ValueKey('group-checkout')));
    await _settle(tester);
    expect(find.text('−₹62'), findsOneWidget, reason: 'discount = normal − agreed, from server values');
    await tester.tap(find.byKey(const ValueKey('group-confirm-order')));
    await _settle(tester);
    final body = repo.posts['POST groups/$gid/checkout']!;
    expect(body['proposalId'], pid);
    expect(body.containsKey('finalPayablePaise'), isFalse, reason: 'the app never sends a price');
    expect(find.text('Order order-1'), findsOneWidget);
  });

  testWidgets('rejected: clear message and alternatives entry for the organizer', (tester) async {
    final repo = GroupFake(groupFixture(status: 'REJECTED', proposal: proposalFixture('REJECTED')));
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid));
    await _settle(tester);
    expect(find.text('Restaurant declined your proposal'), findsOneWidget);
    expect(find.textContaining('find another restaurant that can prepare a similar group meal'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-alternatives')), findsOneWidget);
  });

  testWidgets('hub: join with a code', (tester) async {
    final repo = GroupFake(groupFixture(organizer: false));
    await _mount(tester, repo, const GroupHubScreen());
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('join-code')), 'abcd-2345');
    await tester.tap(find.byKey(const ValueKey('join-submit')));
    await _settle(tester);
    expect(repo.posts['POST groups/join'], {'code': 'abcd-2345'});
    expect(find.text('Room $gid'), findsOneWidget);
  });

  testWidgets('owner: pending request shows items and discount; counteroffer range enforced; accept calls the outlet endpoint', (tester) async {
    final repo = GroupFake(groupFixture())
      ..proposals = [
        {'id': pid, 'groupReference': 'GRP-11111111', 'groupName': 'Friday lunch', 'restaurantId': 'deccan-handi-kphb', 'restaurantName': 'Deccan Handi & Dum', 'outletLocality': 'Kukatpally / KPHB, Hyderabad',
          'memberCount': 2, 'items': [{'name': 'Chicken Dum Biryani', 'quantity': 2, 'variant': null, 'addOns': []}], 'status': 'PENDING', 'normalTotalPaise': 57200, 'proposedTotalPaise': 46000,
          'requestedReductionPaise': 11200, 'requestedReductionPercent': 19.58, 'counterTotalPaise': null, 'agreedTotalPaise': null, 'minAllowedTotalPaise': 40040,
          'responseExpiresAt': DateTime.now().add(const Duration(minutes: 10)).toIso8601String(), 'offerExpiresAt': null, 'orderId': null},
      ];
    await _mount(tester, repo, const OwnerGroupProposalsScreen(restaurantId: 'deccan-handi-kphb'), size: const Size(360, 900));
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.text('2 × Chicken Dum Biryani'), findsOneWidget);
    expect(find.textContaining('19.58%'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('owner-counter-$pid')));
    await _settle(tester);
    await tester.enterText(find.byKey(const ValueKey('owner-counter-amount')), '700');
    await tester.tap(find.byKey(const ValueKey('owner-counter-send')));
    await _settle(tester);
    expect(find.textContaining('Must be above'), findsOneWidget, reason: 'above the normal total is refused');
    await tester.enterText(find.byKey(const ValueKey('owner-counter-amount')), '510');
    await tester.tap(find.byKey(const ValueKey('owner-counter-send')));
    await _settle(tester);
    expect(repo.posts['POST restaurant/group-proposals/$pid/counter'], {'counterTotalPaise': 51000});
    await tester.tap(find.byKey(const ValueKey('owner-accept-$pid')));
    await _settle(tester);
    expect(repo.calls, contains('POST restaurant/group-proposals/$pid/accept'));
  });

  testWidgets('split bill: shares per person, organizer switches to equal split, shared dish picker', (tester) async {
    final repo = GroupFake(groupFixture());
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid), size: const Size(360, 3800), text: 1.5);
    await _settle(tester);
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('group-split')), findsOneWidget);
    expect(find.text('₹201.35'), findsOneWidget);
    expect(find.text('₹370.65'), findsOneWidget);
    expect(find.textContaining('Shares add up to ₹572'), findsOneWidget);
    expect(find.text('Shared: Asha + Bala'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('split-u-b')));
    await tester.tap(find.byKey(const ValueKey('split-u-b')));
    await _settle(tester);
    expect(find.text('Chicken Dum Biryani (1/2)'), findsOneWidget);
    await tester.ensureVisible(find.text('Equally'));
    await tester.tap(find.text('Equally'));
    await _settle(tester);
    expect(repo.posts['POST groups/$gid/split'], {'method': 'EQUAL', 'expectedVersion': 7});
    await tester.ensureVisible(find.byKey(const ValueKey('share-i-2')));
    await tester.tap(find.byKey(const ValueKey('share-i-2')));
    await _settle(tester);
    await tester.tap(find.byKey(const ValueKey('sharer-u-a')));
    await tester.tap(find.byKey(const ValueKey('share-save')));
    await _settle(tester);
    final body = repo.posts['PATCH groups/$gid/items/i-2/share']!;
    expect((body['memberIds'] as List).toSet(), {'u-a', 'u-b'});
  });

  testWidgets('member cannot change the split method', (tester) async {
    final repo = GroupFake(groupFixture(organizer: false));
    await _mount(tester, repo, const GroupRoomScreen(groupId: gid), size: const Size(393, 2400));
    await _settle(tester);
    expect(find.text('The organizer chooses how to split.'), findsOneWidget);
    await tester.ensureVisible(find.text('Equally'));
    await tester.tap(find.text('Equally'));
    await _settle(tester);
    expect(repo.posts.containsKey('POST groups/$gid/split'), isFalse);
  });
}
