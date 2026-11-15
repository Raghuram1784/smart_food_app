import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:share_plus/share_plus.dart';

import '../commerce/commerce_repository.dart';

/// Group order API (backend is the source of truth; the app never computes prices).
class GroupApi {
  final CommerceRepository repo;
  GroupApi(this.repo);

  Future<Json> create({required String restaurantId, required String addressId, String? name}) async =>
      Json.from(await repo.request('POST', 'groups', {'restaurantId': restaurantId, 'addressId': addressId, 'name': ?name}));
  Future<Json> join({String? token, String? code}) async => Json.from(await repo.request('POST', 'groups/join', {'token': ?token, 'code': ?code}));
  Future<List<Json>> mine() async => [for (final g in await repo.request('GET', 'groups') as List) Json.from(g as Map)];
  Future<Json> get(String id) async => Json.from(await repo.request('GET', 'groups/$id'));
  Future<Json> invite(String id) async => Json.from(await repo.request('POST', 'groups/$id/invite'));
  Future<Json> addItem(String id, {required String menuItemId, required int quantity, String? variantId, List<String> addOnIds = const [], required int expectedRevision, String? forMemberId}) async =>
      Json.from(await repo.request('POST', 'groups/$id/items',
          {'menuItemId': menuItemId, 'quantity': quantity, 'variantId': ?variantId, 'addOnIds': addOnIds, 'expectedRevision': expectedRevision, 'forMemberId': ?forMemberId}));

  /// "Order for friends": people added by name only, managed by the organizer on this phone.
  Future<Json> addGuest(String id, String name, int expectedVersion) async => Json.from(await repo.request('POST', 'groups/$id/guests', {'name': name, 'expectedVersion': expectedVersion}));
  Future<Json> removeGuest(String id, String guestId, int expectedVersion) async => Json.from(await repo.request('DELETE', 'groups/$id/guests/$guestId?expectedVersion=$expectedVersion'));
  Future<Json> setQuantity(String id, String itemId, int quantity, int expectedRevision) async =>
      Json.from(await repo.request('PATCH', 'groups/$id/items/$itemId', {'quantity': quantity, 'expectedRevision': expectedRevision}));
  Future<Json> removeItem(String id, String itemId, int expectedRevision) async => Json.from(await repo.request('DELETE', 'groups/$id/items/$itemId?expectedRevision=$expectedRevision'));
  Future<void> leave(String id) async => repo.request('POST', 'groups/$id/leave');
  Future<Json> action(String id, String action, int expectedVersion) async => Json.from(await repo.request('POST', 'groups/$id/$action', {'expectedVersion': expectedVersion}));
  Future<Json> propose(String id, int proposedTotalPaise, int expectedVersion) async =>
      Json.from(await repo.request('POST', 'groups/$id/proposals', {'proposedTotalPaise': proposedTotalPaise, 'expectedVersion': expectedVersion}));
  Future<Json> answerCounter(String id, String proposalId, bool accept, int expectedVersion) async =>
      Json.from(await repo.request('POST', 'groups/$id/proposals/$proposalId/counter', {'answer': accept ? 'accept' : 'decline', 'expectedVersion': expectedVersion}));
  Future<Json> share(String id, String itemId, List<String> memberIds, int expectedVersion) async =>
      Json.from(await repo.request('PATCH', 'groups/$id/items/$itemId/share', {'memberIds': memberIds, 'expectedVersion': expectedVersion}));
  Future<Json> setSplit(String id, String method, int expectedVersion) async => Json.from(await repo.request('POST', 'groups/$id/split', {'method': method, 'expectedVersion': expectedVersion}));
  Future<Json> alternatives(String id) async => Json.from(await repo.request('GET', 'groups/$id/alternatives'));
  Future<Json> switchTo(String id, String restaurantId, int expectedVersion) async =>
      Json.from(await repo.request('POST', 'groups/$id/switch', {'restaurantId': restaurantId, 'expectedVersion': expectedVersion}));
  Future<Json> checkout(String id, String proposalId, int expectedVersion, String idempotencyKey, {Json schedule = const {}, String? paymentMethod}) async =>
      Json.from(await repo.request('POST', 'groups/$id/checkout', {'proposalId': proposalId, 'expectedVersion': expectedVersion, 'idempotencyKey': idempotencyKey, ...schedule, 'paymentMethod': ?paymentMethod}));

  // Restaurant owner
  Future<List<Json>> ownerProposals({String? restaurantId}) async =>
      [for (final p in await repo.request('GET', 'restaurant/group-proposals${restaurantId == null ? '' : '?restaurantId=$restaurantId'}') as List) Json.from(p as Map)];
  Future<Json> ownerRespond(String proposalId, String action, {int? counterTotalPaise, String? note}) async =>
      Json.from(await repo.request('POST', 'restaurant/group-proposals/$proposalId/$action', {'counterTotalPaise': ?counterTotalPaise, 'note': ?note}));
}

final groupApiProvider = Provider<GroupApi>((ref) => GroupApi(ref.watch(commerceRepositoryProvider)));
final groupProvider = FutureProvider.autoDispose.family<Json, String>((ref, id) => ref.watch(groupApiProvider).get(id));
final myGroupsProvider = FutureProvider.autoDispose<List<Json>>((ref) {
  if (ref.watch(customerIdProvider) == null) return const [];
  return ref.watch(groupApiProvider).mine();
});

/// Invite details are only returned when created or rotated; keep them for this app session.
class InviteCache extends Notifier<Map<String, Json>> {
  @override
  Map<String, Json> build() {
    ref.watch(customerIdProvider);
    return const {};
  }

  void put(String groupId, Json invite) => state = {...state, groupId: invite};
}

final inviteCacheProvider = NotifierProvider<InviteCache, Map<String, Json>>(InviteCache.new);

String inviteMessage(Json invite, {String? groupName, String? restaurant}) {
  final url = invite['inviteUrl'] as String?;
  return [
    'Join my group order${groupName == null ? '' : ' "$groupName"'}${restaurant == null ? '' : ' from $restaurant'}.',
    'Open the app → Group Order → Join, and enter code ${invite['joinCode']}.',
    if (url != null) 'Or open: $url',
  ].join('\n');
}

Future<void> shareInvite(Json invite, {String? groupName, String? restaurant}) async {
  final text = inviteMessage(invite, groupName: groupName, restaurant: restaurant);
  try {
    await SharePlus.instance.share(ShareParams(text: text, subject: 'Group order invite'));
  } catch (_) {
    await Clipboard.setData(ClipboardData(text: text));
  }
}

String newIdempotencyKey() {
  final r = Random.secure();
  final b = List<int>.generate(16, (_) => r.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-${h.substring(16, 20)}-${h.substring(20)}';
}
