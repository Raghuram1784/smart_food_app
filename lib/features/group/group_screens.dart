import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/diet_preference.dart';
import '../commerce/commerce_repository.dart';
import '../commerce/live_orders.dart';
import '../finder/finder_theme.dart';
import '../location/delivery_destination.dart';
import 'group_api.dart';

String groupError(Object e) {
  if (e is DioException) {
    final msg = (e.response?.data is Map) ? ((e.response!.data as Map)['error']?['message'] ?? (e.response!.data as Map)['message']) : null;
    if (msg is String && msg.isNotEmpty) return msg;
    if (msg is List && msg.isNotEmpty) return msg.join(', ');
    if (e.response == null) return 'Can\'t reach the server. Check your connection and try again.';
  }
  return commerceError(e);
}

void _toast(BuildContext context, String text) =>
    ScaffoldMessenger.of(context)..hideCurrentSnackBar()..showSnackBar(SnackBar(content: Text(text)));

String _left(String? iso) {
  final t = iso == null ? null : DateTime.tryParse(iso)?.toLocal();
  if (t == null) return '';
  final d = t.difference(DateTime.now());
  if (d.isNegative) return 'expired';
  if (d.inHours >= 1) return '${d.inHours} h ${d.inMinutes % 60} min left';
  return '${d.inMinutes} min ${d.inSeconds % 60} s left';
}

const _statusLabel = {
  'OPEN': 'Open · adding food', 'LOCKED': 'Locked', 'PROPOSED': 'Waiting for restaurant', 'COUNTERED': 'Counteroffer received',
  'ACCEPTED': 'Price accepted', 'REJECTED': 'Request declined', 'ORDERED': 'Order placed', 'CANCELED': 'Canceled', 'EXPIRED': 'Expired',
};

// ===================================================================== Start a group (from a restaurant)
/// Two ways to order together, on top of the same group order:
/// `friends`: the organizer adds people by name and picks everyone's food on this phone;
/// `invite`: friends join with a code or link and add their own food.
const groupModeFriends = 'friends', groupModeInvite = 'invite';

Future<void> startGroupOrder(BuildContext context, WidgetRef ref, {required String restaurantId, required String restaurantName, String? mode}) async {
  final address = ref.read(deliveryDestinationProvider).asData?.value;
  if (address == null) {
    _toast(context, 'Choose a delivery address first (Cart → Delivering to).');
    return;
  }
  final name = TextEditingController();
  final chosen = mode ?? await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    useRootNavigator: true,
    builder: (context) {
      final c = FinderColors.of(context);
      final text = Theme.of(context).textTheme;
      return Padding(
        padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Start a group order', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('Pick everyone\'s food yourself, or invite friends to add their own. Then ask $restaurantName for a group price.', style: text.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: 14),
          _InfoLine(icon: Icons.storefront_outlined, text: restaurantName),
          _InfoLine(icon: Icons.place_outlined, text: 'Delivering to ${destinationTitle(address)}'),
          const _InfoLine(icon: Icons.timer_outlined, text: 'Group stays open for 2 hours'),
          const _InfoLine(icon: Icons.account_balance_wallet_outlined, text: 'You (the organizer) pay the final order total'),
          const SizedBox(height: 10),
          TextField(key: const ValueKey('group-name'), controller: name, maxLength: 60, decoration: const InputDecoration(labelText: 'Group name (optional)', counterText: '')),
          const SizedBox(height: 14),
          FilledButton.icon(
            key: const ValueKey('group-create-friends'),
            style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest),
            onPressed: () => Navigator.pop(context, groupModeFriends),
            icon: const Icon(Icons.edit_note),
            label: const Text('Order for friends'),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const ValueKey('group-create'),
            onPressed: () => Navigator.pop(context, groupModeInvite),
            icon: const Icon(Icons.share_outlined),
            label: const Text('Invite friends'),
          ),
        ]),
      );
    },
  );
  if (chosen == null || !context.mounted) return;
  try {
    final r = await ref.read(groupApiProvider).create(restaurantId: restaurantId, addressId: address['id'] as String, name: name.text.trim().isEmpty ? null : name.text.trim());
    final group = Json.from(r['group'] as Map);
    ref.read(inviteCacheProvider.notifier).put(group['id'] as String, Json.from(r['invite'] as Map));
    ref.invalidate(myGroupsProvider);
    if (context.mounted) context.push('/groups/${group['id']}?${chosen == groupModeFriends ? 'friends' : 'invite'}=1');
  } catch (e) {
    if (context.mounted) _toast(context, groupError(e));
  }
}

class _InfoLine extends StatelessWidget {
  final IconData icon;
  final String text;
  const _InfoLine({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(children: [
        Icon(icon, size: 18, color: c.forest),
        const SizedBox(width: 10),
        Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
      ]),
    );
  }
}

// ===================================================================== Hub: my groups + join
class GroupHubScreen extends ConsumerStatefulWidget {
  const GroupHubScreen({super.key});
  @override
  ConsumerState<GroupHubScreen> createState() => _GroupHubScreenState();
}

class _GroupHubScreenState extends ConsumerState<GroupHubScreen> {
  final code = TextEditingController();
  bool joining = false;

  Future<void> _join() async {
    if (joining || code.text.trim().length < 4) return;
    setState(() => joining = true);
    try {
      final g = await ref.read(groupApiProvider).join(code: code.text.trim());
      ref.invalidate(myGroupsProvider);
      if (mounted) context.push('/groups/${g['id']}');
    } catch (e) {
      if (mounted) _toast(context, groupError(e));
    } finally {
      if (mounted) setState(() => joining = false);
    }
  }

  @override
  void dispose() {
    code.dispose();
    super.dispose();
  }

  /// Start a group: choose the restaurant after choosing how to order.
  Future<void> _start(String mode) async {
    if (ref.read(deliveryDestinationProvider).asData?.value == null) {
      _toast(context, 'Choose a delivery address first (Cart → Delivering to).');
      return;
    }
    final picked = await showModalBottomSheet<({String id, String name})>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _RestaurantPicker(mode: mode),
    );
    if (picked == null || !mounted) return;
    await startGroupOrder(context, ref, restaurantId: picked.id, restaurantName: picked.name, mode: mode);
  }

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final groups = ref.watch(myGroupsProvider);
    return Scaffold(
      backgroundColor: c.ivory,
      appBar: AppBar(title: const Text('Group orders'), backgroundColor: c.ivory),
      body: RefreshIndicator(
        onRefresh: () async => ref.invalidate(myGroupsProvider),
        child: ListView(padding: const EdgeInsets.all(16), children: [
          Text('Order together. Save together.', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Choose how to start, pick a restaurant, then ask it for a group price. It can accept, decline or counter.', style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: 10),
          _ModeTile(
            key: const ValueKey('hub-friends'),
            icon: Icons.edit_note,
            title: 'Order for friends',
            subtitle: 'Type their names and pick everyone\'s food on this phone. No app or account needed for them.',
            onTap: () => _start(groupModeFriends),
          ),
          const SizedBox(height: 8),
          _ModeTile(
            key: const ValueKey('hub-invite'),
            icon: Icons.share_outlined,
            title: 'Invite friends',
            subtitle: 'Share a code or link. Each friend adds their own food from their phone.',
            onTap: () => _start(groupModeInvite),
          ),
          ...groups.maybeWhen(
            data: (list) {
              final active = list.where((g) => !['ORDERED', 'CANCELED', 'EXPIRED'].contains(g['status'])).toList();
              if (active.isEmpty) return const <Widget>[];
              return [
                const SizedBox(height: 20),
                Text('Resume', style: text.titleMedium),
                const SizedBox(height: 8),
                for (final g in active) _GroupTile(g: g, key: ValueKey('resume-${g['id']}')),
              ];
            },
            orElse: () => const <Widget>[],
          ),
          const SizedBox(height: 20),
          Text('Join with a code', style: text.titleMedium),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
              child: TextField(
                key: const ValueKey('join-code'),
                controller: code,
                textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(hintText: 'ABCD-1234'),
                onSubmitted: (_) => _join(),
              ),
            ),
            const SizedBox(width: 8),
            FilledButton(
              key: const ValueKey('join-submit'),
              style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest),
              onPressed: joining ? null : _join,
              child: Text(joining ? 'Joining…' : 'Join'),
            ),
          ]),
          const SizedBox(height: 20),
          Text('Past group orders', style: text.titleMedium),
          const SizedBox(height: 8),
          ...groups.when(
            loading: () => [const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [Text(groupError(e))],
            data: (list) {
              final past = list.where((g) => ['ORDERED', 'CANCELED', 'EXPIRED'].contains(g['status'])).toList();
              return past.isEmpty
                  ? [Text('No past group orders yet.', style: text.bodyMedium?.copyWith(color: c.muted))]
                  : [for (final g in past) _GroupTile(g: g, key: ValueKey('group-${g['id']}'))];
            },
          ),
        ]),
      ),
    );
  }
}

/// Deep link `/group/{token}`: join after sign-in, then open the room.
class GroupJoinLinkScreen extends ConsumerStatefulWidget {
  final String token;
  const GroupJoinLinkScreen({super.key, required this.token});
  @override
  ConsumerState<GroupJoinLinkScreen> createState() => _GroupJoinLinkScreenState();
}

class _GroupJoinLinkScreenState extends ConsumerState<GroupJoinLinkScreen> {
  String? error;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        final g = await ref.read(groupApiProvider).join(token: widget.token);
        if (mounted) context.go('/groups/${g['id']}');
      } catch (e) {
        if (mounted) setState(() => error = groupError(e));
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: const Text('Join group order')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: error == null ? const CircularProgressIndicator() : Text(error!, key: const ValueKey('join-error'), textAlign: TextAlign.center),
          ),
        ),
      );
}

// ===================================================================== Group room
class GroupRoomScreen extends ConsumerStatefulWidget {
  final String groupId;
  final bool showInvite, showPeople;
  const GroupRoomScreen({super.key, required this.groupId, this.showInvite = false, this.showPeople = false});
  @override
  ConsumerState<GroupRoomScreen> createState() => _GroupRoomScreenState();
}

class _GroupRoomScreenState extends ConsumerState<GroupRoomScreen> {
  Timer? ticker;
  bool busy = false;

  @override
  void initState() {
    super.initState();
    ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    if (widget.showInvite) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final g = await ref.read(groupProvider(widget.groupId).future).catchError((_) => <String, dynamic>{});
        if (mounted && g.isNotEmpty) _invite(g);
      });
    }
    if (widget.showPeople) WidgetsBinding.instance.addPostFrameCallback((_) => _people());
  }

  @override
  void dispose() {
    ticker?.cancel();
    super.dispose();
  }

  void _refresh() {
    ref.invalidate(groupProvider(widget.groupId));
    ref.invalidate(myGroupsProvider); // keeps the hub and the Home badge current
  }

  Future<void> _run(Future<void> Function(GroupApi api) work, {String? success}) async {
    if (busy) return;
    setState(() => busy = true);
    try {
      await work(ref.read(groupApiProvider));
      if (success != null && mounted) _toast(context, success);
    } catch (e) {
      if (mounted) _toast(context, groupError(e));
    } finally {
      _refresh();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _invite(Json g) async {
    var invite = ref.read(inviteCacheProvider)[widget.groupId];
    if (invite == null) {
      try {
        invite = await ref.read(groupApiProvider).invite(widget.groupId);
        ref.read(inviteCacheProvider.notifier).put(widget.groupId, invite);
      } catch (e) {
        if (mounted) _toast(context, groupError(e));
        return;
      }
    }
    if (!mounted) return;
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final inv = invite;
    await showModalBottomSheet<void>(
      context: context,
      useRootNavigator: true,
      builder: (context) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Invite friends', style: text.titleLarge),
          const SizedBox(height: 4),
          Text('They open Group Order → Join and enter this code. It works until the group locks or expires.', style: text.bodyMedium?.copyWith(color: c.muted)),
          const SizedBox(height: 16),
          Center(
            child: SelectableText(inv['joinCode'] as String, key: const ValueKey('invite-code'),
                style: text.headlineMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w900, letterSpacing: 4)),
          ),
          if (inv['inviteUrl'] != null) ...[const SizedBox(height: 8), SelectableText(inv['inviteUrl'] as String, textAlign: TextAlign.center, style: text.bodySmall)],
          const SizedBox(height: 16),
          Row(children: [
            Expanded(
              child: OutlinedButton.icon(
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: inviteMessage(inv, groupName: g['name'] as String?, restaurant: (g['restaurant'] as Map)['name'] as String)));
                  if (context.mounted) _toast(context, 'Invite copied');
                },
                icon: const Icon(Icons.copy),
                label: const Text('Copy'),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: FilledButton.icon(
                key: const ValueKey('invite-share'),
                style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest),
                onPressed: () => shareInvite(inv, groupName: g['name'] as String?, restaurant: (g['restaurant'] as Map)['name'] as String),
                icon: const Icon(Icons.ios_share),
                label: const Text('Share'),
              ),
            ),
          ]),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(liveOrdersProvider, (_, next) {
      final u = next.asData?.value;
      if (u != null && (u.groupId == widget.groupId || u.reconcile)) _refresh();
    });
    final c = FinderColors.of(context);
    final group = ref.watch(groupProvider(widget.groupId));
    return Scaffold(
      backgroundColor: c.ivory,
      appBar: AppBar(
        backgroundColor: c.forest,
        foregroundColor: c.onForest,
        title: group.maybeWhen(
          data: (g) => Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text((g['name'] as String?) ?? 'Group order', maxLines: 1, overflow: TextOverflow.ellipsis),
            Text((g['restaurant'] as Map)['name'] as String, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .8))),
          ]),
          orElse: () => const Text('Group order'),
        ),
        actions: [
          IconButton(tooltip: 'Refresh', onPressed: _refresh, icon: const Icon(Icons.refresh)),
          group.maybeWhen(
            data: (g) => (g['permissions'] as Map)['canInvite'] == true
                ? IconButton(key: const ValueKey('group-invite'), tooltip: 'Invite friends', onPressed: () => _invite(g), icon: const Icon(Icons.person_add_alt_1_outlined))
                : const SizedBox.shrink(),
            orElse: () => const SizedBox.shrink(),
          ),
        ],
      ),
      body: group.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Padding(padding: const EdgeInsets.all(24), child: Text(groupError(e), textAlign: TextAlign.center))),
        data: (g) => RefreshIndicator(
          onRefresh: () async => _refresh(),
          child: ListView(
            key: const ValueKey('group-room'),
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
            children: [
              _Summary(g: g),
              const SizedBox(height: 12),
              _Members(g: g, onAddPerson: _people, onRemovePerson: (m) => _removePerson(g, m)),
              const SizedBox(height: 12),
              _StatusPanel(g: g, busy: busy, run: _run, onAlternatives: () => _alternatives(g), onCheckout: () => _checkout(g), onPropose: () => _propose(g)),
              const SizedBox(height: 12),
              _SharedCart(g: g, busy: busy, run: _run, onAdd: (forMemberId) => _addFood(g, forMemberId: forMemberId)),
              if (g['pricing'] != null) ...[const SizedBox(height: 12), _PriceCard(g: g)],
              if (g['split'] != null) ...[const SizedBox(height: 12), _SplitCard(g: g, busy: busy, run: _run)],
              if (g['pricingError'] != null)
                Padding(padding: const EdgeInsets.only(top: 12), child: Text(g['pricingError'].toString(), style: TextStyle(color: c.warn))),
            ],
          ),
        ),
      ),
    );
  }

  // ------------------------------------------------------------- sheets
  Future<void> _addFood(Json g, {String? forMemberId}) async {
    final restaurantId = (g['restaurant'] as Map)['id'] as String;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _AddFoodSheet(groupId: widget.groupId, restaurantId: restaurantId, onAdded: _refresh, forMemberId: forMemberId),
    );
  }

  /// "Order for friends": add people by name (no account, invite or OTP for them).
  Future<void> _people() async {
    await showDialog<void>(context: context, useRootNavigator: true, builder: (_) => _PeopleDialog(groupId: widget.groupId, onChanged: _refresh));
    _refresh();
  }

  Future<void> _removePerson(Json g, Map m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Remove ${m['name']}?'),
        content: const Text('Their food is removed from the group cart too.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep')),
          FilledButton(key: const ValueKey('guest-remove-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Remove')),
        ],
      ),
    );
    if (ok == true) await _run((api) => api.removeGuest(widget.groupId, m['userId'] as String, g['version'] as int), success: '${m['name']} removed');
  }

  Future<void> _propose(Json g) async {
    final p = Json.from(g['pricing'] as Map);
    final range = Json.from(g['negotiationRange'] as Map);
    final normal = p['normalTotalPaise'] as int, min = range['minAllowedTotalPaise'] as int;
    final amount = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _ProposeSheet(normalPaise: normal, minPaise: min, maxDiscountBps: range['maxDiscountBps'] as int, pricing: p),
    );
    if (amount == null) return;
    await _run((api) => api.propose(widget.groupId, amount, g['version'] as int), success: 'Price request sent to the restaurant');
  }

  Future<void> _alternatives(Json g) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useRootNavigator: true,
      builder: (_) => _AlternativesSheet(group: g, onSwitched: _refresh),
    );
  }

  Future<void> _checkout(Json g) async {
    final prop = Json.from(g['proposal'] as Map);
    final agreed = prop['agreedTotalPaise'] as int, normal = prop['normalTotalPaise'] as int;
    final c = FinderColors.of(context);
    final ok = await showDialog<bool>(
      context: context,
      useRootNavigator: true,
      builder: (context) => AlertDialog(
        title: const Text('Place the group order?'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${(g['restaurant'] as Map)['name']} · ${(g['items'] as List).fold<int>(0, (n, i) => n + ((i as Map)['quantity'] as int))} items from ${g['memberCount']} people'),
          const SizedBox(height: 10),
          _row(context, 'Normal total', rupees(normal)),
          _row(context, 'Group discount', '−${rupees(normal - agreed)}', color: c.success),
          const Divider(),
          _row(context, 'You pay', rupees(agreed), bold: true),
          const SizedBox(height: 8),
          Text('You pay the full order total (demo checkout, no real payment). Delivery goes to your selected address.', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Not yet')),
          FilledButton(key: const ValueKey('group-confirm-order'), onPressed: () => Navigator.pop(context, true), child: const Text('Place order')),
        ],
      ),
    );
    if (ok != true) return;
    String? orderId;
    await _run((api) async {
      final r = await api.checkout(widget.groupId, prop['id'] as String, g['version'] as int, newIdempotencyKey());
      orderId = r['orderId'] as String;
    }, success: 'Group order placed');
    if (orderId != null && mounted) context.push('/orders/$orderId');
  }
}

Widget _row(BuildContext context, String label, String value, {bool bold = false, Color? color}) {
  final style = bold ? Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: color) : Theme.of(context).textTheme.bodyMedium?.copyWith(color: color);
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 2),
    child: Row(children: [Expanded(child: Text(label, style: style)), Text(value, style: style)]),
  );
}

class _Card extends StatelessWidget {
  final Widget child;
  final Color? color;
  final Key? cardKey;
  const _Card({required this.child, this.color, this.cardKey});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Container(
      key: cardKey,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(color: color ?? c.card, borderRadius: BorderRadius.circular(18), border: Border.all(color: c.outline)),
      child: child,
    );
  }
}

class _Summary extends StatelessWidget {
  final Json g;
  const _Summary({required this.g});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final r = Json.from(g['restaurant'] as Map);
    final status = g['status'] as String;
    return _Card(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Wrap(spacing: 8, runSpacing: 6, crossAxisAlignment: WrapCrossAlignment.center, children: [
          Text(r['name'] as String, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          DecoratedBox(
            decoration: BoxDecoration(color: c.paleGreen, borderRadius: BorderRadius.circular(999)),
            child: Padding(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), child: Text(_statusLabel[status] ?? status, key: const ValueKey('group-status'), style: text.labelMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w800))),
          ),
        ]),
        if (r['locality'] != null) Text((r['locality'] as String).split(',').first, style: text.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: 8),
        if (!['ORDERED', 'CANCELED', 'EXPIRED'].contains(status)) _InfoLine(icon: Icons.timer_outlined, text: 'Group closes in ${_left(g['expiresAt'] as String?)}'),
        _InfoLine(icon: Icons.account_balance_wallet_outlined, text: g['paymentNote'] as String),
      ]),
    );
  }
}

class _Members extends StatelessWidget {
  final Json g;
  final VoidCallback onAddPerson;
  final void Function(Map member) onRemovePerson;
  const _Members({required this.g, required this.onAddPerson, required this.onRemovePerson});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final members = (g['members'] as List).cast<Map>();
    final manage = (g['permissions'] as Map)['canManageGuests'] == true;
    return _Card(
      cardKey: const ValueKey('group-members'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: Text('${members.length} ${members.length == 1 ? 'person' : 'people'}', style: text.titleSmall)),
          if (manage)
            TextButton.icon(key: const ValueKey('group-add-person'), onPressed: onAddPerson, icon: const Icon(Icons.person_add_alt, size: 18), label: const Text('Add person')),
        ]),
        if (manage && members.length == 1)
          Text('Ordering for friends? Add their names, then pick food for each person.', style: text.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: 8),
        Wrap(spacing: 10, runSpacing: 8, children: [
          for (final m in members)
            InkWell(
              key: ValueKey('member-${m['userId']}'),
              borderRadius: BorderRadius.circular(12),
              onTap: manage && m['isGuest'] == true ? () => onRemovePerson(m) : null,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
              CircleAvatar(
                radius: 20,
                backgroundColor: m['isOrganizer'] == true ? c.gold : c.paleGreen,
                child: Text(((m['name'] as String).trim().isEmpty ? '?' : (m['name'] as String).trim()[0]).toUpperCase(), style: text.titleMedium?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 2),
              SizedBox(
                width: 68,
                child: Text('${m['isYou'] == true ? 'You' : m['name']}${m['isOrganizer'] == true ? ' ★' : ''}', textAlign: TextAlign.center, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.labelSmall),
              ),
              if (m['isGuest'] == true) Text('added by you', style: text.labelSmall?.copyWith(color: c.muted, fontSize: 10)),
            ])),
        ]),
      ]),
    );
  }
}

class _SharedCart extends StatelessWidget {
  final Json g;
  final bool busy;
  final Future<void> Function(Future<void> Function(GroupApi), {String? success}) run;
  final void Function(String? forMemberId) onAdd;
  const _SharedCart({required this.g, required this.busy, required this.run, required this.onAdd});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final items = (g['items'] as List).cast<Map>();
    final editable = (g['permissions'] as Map)['canEditOwnItems'] == true;
    final members = (g['members'] as List).cast<Map>();
    final org = g['isOrganizer'] == true;
    final hasGuests = members.any((m) => m['isGuest'] == true);
    // On one phone the organizer sees a section per person, even before they have food.
    final byMember = <String, ({String name, Map? member, List<Map> items})>{};
    if (org && hasGuests) {
      for (final m in members) {
        byMember[m['userId'] as String] = (name: m['name'] as String, member: m, items: <Map>[]);
      }
    }
    for (final i in items) {
      final id = i['memberId'] as String;
      byMember.putIfAbsent(id, () => (name: i['memberName'] as String, member: members.where((m) => m['userId'] == id).firstOrNull, items: <Map>[])).items.add(i);
    }
    final rev = g['cartRevision'] as int;
    return _Card(
      cardKey: const ValueKey('group-cart'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Shared cart', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          if (editable)
            FilledButton.icon(
              key: const ValueKey('group-add-food'),
              style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest, minimumSize: const Size(40, 40)),
              onPressed: busy ? null : () => onAdd(null),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add food'),
            ),
        ]),
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(hasGuests && org ? 'No food yet. Tap "Add" next to each person to pick their dishes.' : 'No food yet. Everyone adds their own dishes.', style: text.bodyMedium?.copyWith(color: c.muted)),
          ),
        for (final entry in byMember.entries) ...[
          const SizedBox(height: 10),
          Row(children: [
            Expanded(child: Text(entry.value.name, style: text.labelLarge?.copyWith(color: c.muted))),
            if (editable && org && hasGuests && (entry.value.member?['isGuest'] == true || entry.value.member?['isYou'] == true))
              TextButton.icon(
                key: ValueKey('add-for-${entry.key}'),
                style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
                onPressed: busy ? null : () => onAdd(entry.value.member?['isGuest'] == true ? entry.key : null),
                icon: const Icon(Icons.add, size: 16),
                label: const Text('Add'),
              ),
          ]),
          if (entry.value.items.isEmpty) Text('Nothing yet', style: text.bodySmall?.copyWith(color: c.muted)),
          for (final i in entry.value.items)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(children: [
                if (i['isVegetarian'] != null) Padding(padding: const EdgeInsets.only(right: 6), child: VegMark(veg: i['isVegetarian'] == true)),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(i['name'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    if ((i['variant'] as Map?)?['name'] != null || (i['addOns'] as List).isNotEmpty)
                      Text([if ((i['variant'] as Map?)?['name'] != null) (i['variant'] as Map)['name'], for (final a in i['addOns'] as List) '+ ${(a as Map)['name']}'].join(' · '),
                          style: text.bodySmall?.copyWith(color: c.muted)),
                    if (i['available'] == false) Text('No longer available', style: text.bodySmall?.copyWith(color: c.warn)),
                    if ((i['sharedWithNames'] as List? ?? []).isNotEmpty) Text('Shared: ${(i['sharedWithNames'] as List).join(' + ')}', style: text.bodySmall?.copyWith(color: c.forest)),
                    Text(rupees(i['lineTotalPaise'] as int), style: text.bodySmall?.copyWith(color: c.forest, fontWeight: FontWeight.w700)),
                  ]),
                ),
                if (i['canShare'] == true && (g['members'] as List).length > 1 && !['ORDERED', 'CANCELED', 'EXPIRED'].contains(g['status']))
                  IconButton(
                    key: ValueKey('share-${i['id']}'),
                    tooltip: 'Share this dish',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy ? null : () => _pickSharers(context, g, Json.from(i), run),
                    icon: Icon((i['sharedWith'] as List).isEmpty ? Icons.call_split : Icons.people_alt, size: 20, color: (i['sharedWith'] as List).isEmpty ? null : c.forest),
                  ),
                if ((i['canEdit'] ?? i['mine']) == true && editable) ...[
                  IconButton(
                    tooltip: 'Fewer',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy ? null : () => run((api) => (i['quantity'] as int) > 1 ? api.setQuantity(g['id'] as String, i['id'] as String, (i['quantity'] as int) - 1, rev) : api.removeItem(g['id'] as String, i['id'] as String, rev)),
                    icon: Icon((i['quantity'] as int) > 1 ? Icons.remove_circle_outline : Icons.delete_outline, size: 20),
                  ),
                  Text('${i['quantity']}', style: text.titleSmall),
                  IconButton(
                    tooltip: 'More',
                    visualDensity: VisualDensity.compact,
                    onPressed: busy || (i['quantity'] as int) >= 20 ? null : () => run((api) => api.setQuantity(g['id'] as String, i['id'] as String, (i['quantity'] as int) + 1, rev)),
                    icon: const Icon(Icons.add_circle_outline, size: 20),
                  ),
                ] else
                  Padding(padding: const EdgeInsets.only(left: 8), child: Text('× ${i['quantity']}', style: text.titleSmall)),
              ]),
            ),
        ],
      ]),
    );
  }
}

class _PriceCard extends StatelessWidget {
  final Json g;
  const _PriceCard({required this.g});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final p = Json.from(g['pricing'] as Map);
    final people = (g['memberCount'] as int?) ?? 1;
    final total = p['normalTotalPaise'] as int;
    return _Card(
      cardKey: const ValueKey('group-price'),
      color: c.paleGreen,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Normal price (server quote)', style: text.titleSmall),
        const SizedBox(height: 6),
        _row(context, 'Food', rupees((p['itemSubtotalPaise'] as int) + (p['customizationTotalPaise'] as int))),
        if ((p['packagingPaise'] as int) > 0) _row(context, 'Packaging', rupees(p['packagingPaise'] as int)),
        _row(context, 'Delivery', rupees(p['deliveryPaise'] as int)),
        if ((p['platformPaise'] as int) > 0) _row(context, 'Platform fee', rupees(p['platformPaise'] as int)),
        _row(context, 'Taxes', (p['taxPaise'] as int) > 0 ? rupees(p['taxPaise'] as int) : 'None configured'),
        if ((p['discountPaise'] as int) > 0) _row(context, 'Discount', '−${rupees(p['discountPaise'] as int)}'),
        const Divider(),
        _row(context, 'Normal total', rupees(total), bold: true),
        Text('About ${rupees((total / people).round())} per person, for information only.', style: text.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: 6),
        for (final m in (g['contributions'] as List).cast<Map>())
          _row(context, '${m['name']} · ${m['itemCount']} ${m['itemCount'] == 1 ? 'item' : 'items'}', rupees(m['itemTotalPaise'] as int)),
      ]),
    );
  }
}

class _StatusPanel extends StatelessWidget {
  final Json g;
  final bool busy;
  final Future<void> Function(Future<void> Function(GroupApi), {String? success}) run;
  final VoidCallback onAlternatives, onCheckout, onPropose;
  const _StatusPanel({required this.g, required this.busy, required this.run, required this.onAlternatives, required this.onCheckout, required this.onPropose});

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final status = g['status'] as String;
    final perm = Json.from(g['permissions'] as Map);
    final prop = g['proposal'] == null ? null : Json.from(g['proposal'] as Map);
    final id = g['id'] as String, v = g['version'] as int;
    final org = g['isOrganizer'] == true;
    Widget button(String label, VoidCallback? onTap, {Key? key, bool primary = true, IconData? icon}) => Padding(
          padding: const EdgeInsets.only(top: 8),
          child: primary
              ? FilledButton.icon(key: key, style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest), onPressed: busy ? null : onTap, icon: Icon(icon ?? Icons.arrow_forward), label: Text(label))
              : OutlinedButton.icon(key: key, onPressed: busy ? null : onTap, icon: Icon(icon ?? Icons.arrow_forward), label: Text(label)),
        );
    final children = <Widget>[];
    Color bg = c.card;
    switch (status) {
      case 'OPEN':
        children.add(Text(org ? 'When everyone\'s food is in, lock the group to ask the restaurant for a price.' : 'Add your dishes. The organizer locks the group when everyone is ready.', style: text.bodyMedium));
        if (perm['canLock'] == true) children.add(button('Lock group', () => run((api) => api.action(id, 'lock', v), success: 'Group locked'), key: const ValueKey('group-lock'), icon: Icons.lock_outline));
        if (perm['canLeave'] == true) children.add(button('Leave group', () => run((api) => api.leave(id), success: 'You left the group'), primary: false, icon: Icons.logout));
      case 'LOCKED':
        if (prop != null && ['EXPIRED', 'DECLINED'].contains(prop['status'])) {
          children.add(Text(prop['status'] == 'EXPIRED' ? 'The last request or offer expired.' : 'You declined the counteroffer.', style: text.bodyMedium?.copyWith(color: c.warn)));
        }
        children.add(Text(org ? 'The cart is locked. Send the restaurant the total you want to pay.' : 'Locked. Waiting for the organizer to ask the restaurant for a price.', style: text.bodyMedium));
        if (perm['canPropose'] == true && g['pricing'] != null) children.add(button('Propose a group price', onPropose, key: const ValueKey('group-propose'), icon: Icons.handshake_outlined));
        if (perm['canUnlock'] == true) children.add(button('Reopen to change food', () => run((api) => api.action(id, 'unlock', v)), primary: false, icon: Icons.lock_open));
      case 'PROPOSED':
        bg = c.goldBg;
        children.addAll([
          Text('Price request sent', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('You asked for ${rupees(prop!['proposedTotalPaise'] as int)} instead of ${rupees(prop['normalTotalPaise'] as int)} (${rupees(prop['requestedReductionPaise'] as int)} off). Waiting for the restaurant.', style: text.bodyMedium),
          const SizedBox(height: 6),
          Row(children: [Icon(Icons.hourglass_top, size: 18, color: c.charcoal), const SizedBox(width: 6), Expanded(child: Text('Response window: ${_left(prop['responseExpiresAt'] as String?)}', key: const ValueKey('group-waiting')))]),
        ]);
      case 'COUNTERED':
        bg = c.goldBg;
        children.addAll([
          Text('Restaurant offered ${rupees(prop!['counterTotalPaise'] as int)}', key: const ValueKey('group-counter'), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
          Text('You asked for ${rupees(prop['proposedTotalPaise'] as int)}; the normal total is ${rupees(prop['normalTotalPaise'] as int)}.${prop['responseNote'] != null ? '\n“${prop['responseNote']}”' : ''}', style: text.bodyMedium),
          Text('Offer valid: ${_left(prop['offerExpiresAt'] as String?)}', style: text.bodySmall),
        ]);
        if (perm['canRespondToCounter'] == true) {
          children.add(button('Accept ${rupees(prop['counterTotalPaise'] as int)}', () => run((api) => api.answerCounter(id, prop['id'] as String, true, v), success: 'Offer accepted'), key: const ValueKey('group-accept-counter'), icon: Icons.check));
          children.add(button('Decline', () => run((api) => api.answerCounter(id, prop['id'] as String, false, v)), primary: false, icon: Icons.close));
        }
      case 'ACCEPTED':
        bg = c.successBg;
        children.addAll([
          Text('Restaurant accepted ${rupees(prop!['agreedTotalPaise'] as int)}', key: const ValueKey('group-accepted'), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.success)),
          Text('Normal total ${rupees(prop['normalTotalPaise'] as int)} · group discount ${rupees((prop['normalTotalPaise'] as int) - (prop['agreedTotalPaise'] as int))}', style: text.bodyMedium),
          Text('Offer valid: ${_left(prop['offerExpiresAt'] as String?)}', style: text.bodySmall),
        ]);
        if (perm['canCheckout'] == true) children.add(button('Review and place order', onCheckout, key: const ValueKey('group-checkout'), icon: Icons.shopping_bag_outlined));
        if (!org) children.add(Text('The organizer will place the order.', style: text.bodySmall));
      case 'REJECTED':
        bg = c.warnBg;
        children.addAll([
          Text('Restaurant declined your proposal', key: const ValueKey('group-rejected'), style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.warn)),
          if (prop?['responseNote'] != null) Text('“${prop!['responseNote']}”', style: text.bodyMedium),
          Text('Your proposed price wasn\'t accepted. Let\'s find another restaurant that can prepare a similar group meal.', style: text.bodyMedium),
        ]);
        if (org) children.add(button('Find another restaurant', onAlternatives, key: const ValueKey('group-alternatives'), icon: Icons.travel_explore));
        if (perm['canPropose'] == true) children.add(button('Send a different price', onPropose, primary: false, icon: Icons.handshake_outlined));
        if (perm['canUnlock'] == true) children.add(button('Reopen to change food', () => run((api) => api.action(id, 'unlock', v)), primary: false, icon: Icons.lock_open));
      case 'ORDERED':
        bg = c.successBg;
        children.addAll([
          Text('Group order placed', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800, color: c.success)),
          if (org && g['orderId'] != null) button('Track order', () => context.push('/orders/${g['orderId']}'), key: const ValueKey('group-track'), icon: Icons.delivery_dining),
          if (!org) Text('The organizer is tracking delivery.', style: text.bodySmall),
        ]);
      default:
        children.add(Text(status == 'CANCELED' ? 'This group was canceled.' : 'This group has expired.', style: text.bodyMedium));
    }
    if (perm['canCancel'] == true && !['ORDERED'].contains(status)) {
      children.add(Align(
        alignment: Alignment.centerRight,
        child: TextButton(onPressed: busy ? null : () => run((api) => api.action(id, 'cancel', v), success: 'Group canceled'), child: const Text('Cancel group')),
      ));
    }
    return _Card(cardKey: const ValueKey('group-status-panel'), color: bg, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children));
  }
}

// ------------------------------------------------------------- Add food
class _AddFoodSheet extends ConsumerStatefulWidget {
  final String groupId, restaurantId;
  final String? forMemberId;
  final VoidCallback onAdded;
  const _AddFoodSheet({required this.groupId, required this.restaurantId, required this.onAdded, this.forMemberId});
  @override
  ConsumerState<_AddFoodSheet> createState() => _AddFoodSheetState();
}

class _AddFoodSheetState extends ConsumerState<_AddFoodSheet> {
  bool busy = false;
  late String? forMemberId = widget.forMemberId;

  Future<void> _choose(Dish d) async {
    final variants = d.variantOptions.where((v) => v.available).toList();
    final addOns = d.addOnOptions.where((a) => a.available).toList();
    String? variantId = variants.isEmpty ? null : variants.first.id;
    final picked = <String>{};
    var qty = 1;
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, set) => AlertDialog(
          title: Text(d.name),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('₹${d.displayPrice} menu price'),
              if (variants.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Size'),
                for (final v in variants)
                  // ignore: deprecated_member_use
                  RadioListTile<String>(dense: true, value: v.id, groupValue: variantId, onChanged: (x) => set(() => variantId = x), title: Text('${v.name}${v.pricePaise > 0 ? ' (+${rupees(v.pricePaise)})' : ''}')),
              ],
              if (addOns.isNotEmpty) ...[
                const SizedBox(height: 8),
                const Text('Add-ons'),
                for (final a in addOns)
                  CheckboxListTile(dense: true, value: picked.contains(a.id), onChanged: (x) => set(() => x == true ? picked.add(a.id) : picked.remove(a.id)), title: Text('${a.name} (+${rupees(a.pricePaise)})')),
              ],
              const SizedBox(height: 8),
              Row(children: [
                const Text('Quantity'),
                const Spacer(),
                IconButton(onPressed: qty > 1 ? () => set(() => qty--) : null, icon: const Icon(Icons.remove_circle_outline)),
                Text('$qty', key: const ValueKey('add-qty')),
                IconButton(onPressed: qty < 20 ? () => set(() => qty++) : null, icon: const Icon(Icons.add_circle_outline)),
              ]),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(key: const ValueKey('add-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Add to group')),
          ],
        ),
      ),
    );
    if (ok != true || busy) return;
    setState(() => busy = true);
    try {
      final g = await ref.read(groupProvider(widget.groupId).future);
      await ref.read(groupApiProvider).addItem(widget.groupId, menuItemId: d.id, quantity: qty, variantId: variantId, addOnIds: picked.toList(), expectedRevision: g['cartRevision'] as int, forMemberId: forMemberId);
      widget.onAdded();
      final who = forMemberId == null ? '' : ' for ${(g['members'] as List).cast<Map>().where((m) => m['userId'] == forMemberId).firstOrNull?['name'] ?? 'them'}';
      if (mounted) _toast(context, 'Added $qty × ${d.name}$who');
    } catch (e) {
      widget.onAdded();
      if (mounted) _toast(context, groupError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final menu = ref.watch(restaurantMenuProvider(widget.restaurantId));
    final text = Theme.of(context).textTheme;
    final c = FinderColors.of(context);
    final g = ref.watch(groupProvider(widget.groupId)).asData?.value;
    final people = g == null || g['isOrganizer'] != true ? const <Map>[] : (g['members'] as List).cast<Map>().where((m) => m['isYou'] == true || m['isGuest'] == true).toList();
    final forName = forMemberId == null ? null : people.where((m) => m['userId'] == forMemberId).firstOrNull?['name'] as String?;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Row(children: [
            Expanded(child: Text(forName == null ? 'Add your food' : 'Add food for $forName', style: text.titleLarge)),
            if (busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
          ]),
        ),
        if (people.length > 1)
          SizedBox(
            height: 44,
            child: ListView(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: 16), children: [
              for (final m in people)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    key: ValueKey('for-${m['userId']}'),
                    selected: (m['isYou'] == true && forMemberId == null) || m['userId'] == forMemberId,
                    selectedColor: c.paleGreen,
                    label: Text(m['isYou'] == true ? 'You' : m['name'] as String),
                    onSelected: (_) => setState(() => forMemberId = m['isYou'] == true ? null : m['userId'] as String),
                  ),
                ),
            ]),
          ),
        Expanded(
          child: menu.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(groupError(e))),
            data: (m) => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: m.items.where((d) => d.availabilityStatus == 'AVAILABLE').length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final d = m.items.where((d) => d.availabilityStatus == 'AVAILABLE').elementAt(i);
                return ListTile(
                  key: ValueKey('menu-${d.id}'),
                  contentPadding: EdgeInsets.zero,
                  leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: FoodPhoto(d.photoKey, width: 52, height: 52)),
                  title: Row(children: [if (d.isVegetarian != null) Padding(padding: const EdgeInsets.only(right: 6), child: VegMark(veg: d.isVegetarian!)), Expanded(child: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis))]),
                  subtitle: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('₹${d.displayPrice}'), NutritionLine(d.nutrition, dense: true)]),
                  trailing: const Icon(Icons.add_circle_outline),
                  onTap: busy ? null : () => _choose(d),
                );
              },
            ),
          ),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------- Propose
class _ProposeSheet extends StatefulWidget {
  final int normalPaise, minPaise, maxDiscountBps;
  final Json pricing;
  const _ProposeSheet({required this.normalPaise, required this.minPaise, required this.maxDiscountBps, required this.pricing});
  @override
  State<_ProposeSheet> createState() => _ProposeSheetState();
}

class _ProposeSheetState extends State<_ProposeSheet> {
  late final TextEditingController amount;
  String? error;
  @override
  void initState() {
    super.initState();
    final suggestion = ((widget.normalPaise * 0.85) / 100).floor() * 100;
    amount = TextEditingController(text: '${(suggestion < widget.minPaise ? widget.minPaise : suggestion) ~/ 100}');
  }

  @override
  void dispose() {
    amount.dispose();
    super.dispose();
  }

  int? get _paise {
    final r = int.tryParse(amount.text.trim());
    return r == null ? null : r * 100;
  }

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final p = _paise;
    final saving = p == null ? null : widget.normalPaise - p;
    final valid = p != null && p < widget.normalPaise && p >= widget.minPaise;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 4, 20, 20 + MediaQuery.viewInsetsOf(context).bottom),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Propose a group price', style: text.titleLarge),
        const SizedBox(height: 10),
        _row(context, 'Normal total (incl. fees)', rupees(widget.normalPaise), bold: true),
        const SizedBox(height: 10),
        TextField(
          key: const ValueKey('propose-amount'),
          controller: amount,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(labelText: 'Your proposal (₹, final amount you pay)', prefixText: '₹ ', errorText: error),
          onChanged: (_) => setState(() => error = null),
        ),
        const SizedBox(height: 8),
        if (saving != null && saving > 0)
          _row(context, 'Requested savings', '${rupees(saving)} (${(100 * saving / widget.normalPaise).toStringAsFixed(1)}%)', color: valid ? c.success : c.warn),
        Text('This restaurant considers requests down to ${rupees(widget.minPaise)} (up to ${widget.maxDiscountBps / 100}% off). It may accept, decline or counter.', style: text.bodySmall?.copyWith(color: c.muted)),
        const SizedBox(height: 14),
        FilledButton.icon(
          key: const ValueKey('propose-send'),
          style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest),
          onPressed: () {
            if (!valid) {
              setState(() => error = p == null ? 'Enter an amount' : p >= widget.normalPaise ? 'Must be below ${rupees(widget.normalPaise)}' : 'Lowest allowed is ${rupees(widget.minPaise)}');
              return;
            }
            Navigator.pop(context, p);
          },
          icon: const Icon(Icons.send),
          label: const Text('Send proposal'),
        ),
      ]),
    );
  }
}

// ------------------------------------------------------------- Alternatives
class _AlternativesSheet extends ConsumerStatefulWidget {
  final Json group;
  final VoidCallback onSwitched;
  const _AlternativesSheet({required this.group, required this.onSwitched});
  @override
  ConsumerState<_AlternativesSheet> createState() => _AlternativesSheetState();
}

class _AlternativesSheetState extends ConsumerState<_AlternativesSheet> {
  late final Future<Json> future = ref.read(groupApiProvider).alternatives(widget.group['id'] as String);
  bool busy = false;

  Future<void> _switch(Json alt) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Move the group to ${alt['name']}?'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
            for (final m in (alt['mapping'] as List).cast<Map>())
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 3),
                child: Text(m['to'] == null ? '✕ ${m['quantity']} × ${m['from']} — not available, will be removed' : '${(m['to'] as Map)['sameDish'] == true ? '✓' : '≈'} ${m['quantity']} × ${m['from']} → ${(m['to'] as Map)['name']}'),
              ),
            const SizedBox(height: 8),
            Text('The group reopens so everyone can review their dishes. ${alt['name']} has not agreed to any price yet.', style: Theme.of(context).textTheme.bodySmall),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('switch-confirm'), onPressed: () => Navigator.pop(context, true), child: const Text('Move group')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await ref.read(groupApiProvider).switchTo(widget.group['id'] as String, alt['restaurantId'] as String, widget.group['version'] as int);
      widget.onSwitched();
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) _toast(context, groupError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: FutureBuilder<Json>(
        future: future,
        builder: (context, snap) {
          if (snap.hasError) return Center(child: Text(groupError(snap.error!)));
          if (!snap.hasData) return const Center(child: CircularProgressIndicator());
          final alts = (snap.data!['alternatives'] as List).cast<Map>();
          return ListView(padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
            Text('Other restaurants for this meal', style: text.titleLarge),
            const SizedBox(height: 4),
            Text(snap.data!['note'] as String? ?? '', style: text.bodySmall?.copyWith(color: c.muted)),
            if (alts.isEmpty) Padding(padding: const EdgeInsets.only(top: 16), child: Text('No other participating restaurant near you serves similar dishes right now.', style: text.bodyMedium)),
            for (final a in alts)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: _Card(
                  cardKey: ValueKey('alt-${a['restaurantId']}'),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Row(children: [
                      Expanded(child: Text(a['name'] as String, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
                      Text('${a['matchPercent']}% match', style: text.labelLarge?.copyWith(color: c.forest)),
                    ]),
                    if (a['locality'] != null) Text((a['locality'] as String).split(',').first, style: text.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: 6),
                    Text('${a['matchedCount']} of ${a['totalCount']} dishes available', style: text.bodyMedium),
                    for (final m in (a['mapping'] as List).cast<Map>())
                      Text(m['to'] == null ? '✕ ${m['from']} (missing)' : '${(m['to'] as Map)['sameDish'] == true ? '✓' : '≈'} ${m['from']} → ${(m['to'] as Map)['name']}', style: text.bodySmall),
                    const SizedBox(height: 6),
                    _row(context, 'Estimated normal total', rupees(a['estimatedNormalTotalPaise'] as int)),
                    _row(context, 'Lowest price you can propose', rupees(a['lowestProposalPaise'] as int)),
                    Align(
                      alignment: Alignment.centerRight,
                      child: FilledButton(
                        key: ValueKey('alt-switch-${a['restaurantId']}'),
                        style: FilledButton.styleFrom(backgroundColor: c.forest, foregroundColor: c.onForest),
                        onPressed: busy ? null : () => _switch(Json.from(a)),
                        child: const Text('Review and switch'),
                      ),
                    ),
                  ]),
                ),
              ),
          ]);
        },
      ),
    );
  }
}

/// Compact Group Order button for the Home header (under the search bar, on the forest band).
/// Opens the hub: start (for friends or by invite), join with a code, or resume an active group.
class GroupOrderEntry extends ConsumerWidget {
  const GroupOrderEntry({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final active = ref.watch(myGroupsProvider).asData?.value.where((g) => !['ORDERED', 'CANCELED', 'EXPIRED'].contains(g['status'])).length ?? 0;
    return Semantics(
      button: true,
      label: 'Group Order. Order together. Save together.${active > 0 ? ' $active active' : ''}',
      excludeSemantics: true,
      child: Material(
        color: c.onForest.withValues(alpha: .1),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: c.onForest.withValues(alpha: .18))),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          key: const ValueKey('group-entry'),
          onTap: () => context.push('/groups'),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
            child: Row(children: [
              Container(width: 32, height: 32, decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle), child: Icon(Icons.groups_2, size: 18, color: c.forest)),
              const SizedBox(width: 10),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text('Group Order', style: text.titleSmall?.copyWith(color: c.onForest, fontWeight: FontWeight.w800)),
                  Text('Order together. Save together.', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: c.onForest.withValues(alpha: .8))),
                ]),
              ),
              if (active > 0)
                Container(
                  key: const ValueKey('group-entry-active'),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(color: c.gold, borderRadius: BorderRadius.circular(999)),
                  child: Text('$active active', style: text.labelSmall?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
                ),
              Icon(Icons.chevron_right, color: c.onForest),
            ]),
          ),
        ),
      ),
    );
  }
}

class _ModeTile extends StatelessWidget {
  final IconData icon;
  final String title, subtitle;
  final VoidCallback onTap;
  const _ModeTile({super.key, required this.icon, required this.title, required this.subtitle, required this.onTap});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.card,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.outline)),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Container(width: 40, height: 40, decoration: BoxDecoration(color: c.paleGreen, shape: BoxShape.circle), child: Icon(icon, color: c.forest)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Text(subtitle, style: text.bodySmall?.copyWith(color: c.muted)),
              ]),
            ),
            Icon(Icons.chevron_right, color: c.forest),
          ]),
        ),
      ),
    );
  }
}

class _GroupTile extends StatelessWidget {
  final Json g;
  const _GroupTile({super.key, required this.g});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: c.paleGreen, child: Icon(Icons.groups_2_outlined, color: c.forest)),
        title: Text((g['name'] as String?) ?? g['restaurantName'] as String, maxLines: 1, overflow: TextOverflow.ellipsis),
        subtitle: Text('${g['restaurantName']} · ${g['memberCount']} ${g['memberCount'] == 1 ? 'person' : 'people'} · ${_statusLabel[g['status']] ?? g['status']}', maxLines: 2),
        trailing: const Icon(Icons.chevron_right),
        onTap: () => context.push('/groups/${g['id']}'),
      ),
    );
  }
}

/// Restaurants for a new group: kitchens serving the selected delivery area first (the server re-checks).
class _RestaurantPicker extends ConsumerWidget {
  final String mode;
  const _RestaurantPicker({required this.mode});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final area = ref.watch(deliveryServiceAreaProvider);
    final catalog = ref.watch(homeCatalogProvider);
    bool serves(Restaurant r) => area != null && (r.localityName == area.name || r.serviceAreaNames.contains(area.name));
    return SizedBox(
      height: MediaQuery.sizeOf(context).height * .8,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(padding: const EdgeInsets.fromLTRB(20, 0, 20, 4), child: Text('Choose a restaurant', style: text.titleLarge)),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
          child: Text(mode == groupModeFriends ? 'Next, add your friends\' names and pick food for each person.' : 'Next, you\'ll get a code to share with friends.', style: text.bodySmall?.copyWith(color: c.muted)),
        ),
        Expanded(
          child: catalog.when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text(groupError(e))),
            data: (cat) {
              final list = [...cat.restaurants]..sort((a, b) => (serves(b) ? 1 : 0) - (serves(a) ? 1 : 0));
              return ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: list.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (_, i) {
                  final r = list[i];
                  final open = r.operatingStatus == 'OPEN' && r.deliveryAvailable;
                  return ListTile(
                    key: ValueKey('pick-${r.id}'),
                    contentPadding: EdgeInsets.zero,
                    enabled: open,
                    leading: ClipRRect(borderRadius: BorderRadius.circular(10), child: FoodPhoto(r.image, width: 52, height: 52)),
                    title: Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                    subtitle: Text([r.cuisine, if (r.localityName != null) r.localityName!.split(',').first, if (!open) 'Closed now' else if (serves(r)) 'Delivers to you'].join(' · '),
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () => Navigator.pop(context, (id: r.id, name: r.name)),
                  );
                },
              );
            },
          ),
        ),
      ]),
    );
  }
}

/// "Order for friends": add people by name. Each add is saved at once (the server is the source of truth).
class _PeopleDialog extends ConsumerStatefulWidget {
  final String groupId;
  final VoidCallback onChanged;
  const _PeopleDialog({required this.groupId, required this.onChanged});
  @override
  ConsumerState<_PeopleDialog> createState() => _PeopleDialogState();
}

class _PeopleDialogState extends ConsumerState<_PeopleDialog> {
  final name = TextEditingController();
  final added = <String>[];
  String? error;
  bool busy = false;

  @override
  void dispose() {
    name.dispose();
    super.dispose();
  }

  Future<void> _add() async {
    final n = name.text.trim();
    if (n.isEmpty || busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      ref.invalidate(groupProvider(widget.groupId));
      final g = await ref.read(groupProvider(widget.groupId).future);
      await ref.read(groupApiProvider).addGuest(widget.groupId, n, g['version'] as int);
      added.add(n);
      name.clear();
      widget.onChanged();
    } catch (e) {
      error = groupError(e);
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return AlertDialog(
      title: const Text('Who are you ordering for?'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Just type their names. They don\'t need the app, an account or a code. You pick their food and pay the order.', style: text.bodySmall?.copyWith(color: c.muted)),
          const SizedBox(height: 10),
          TextField(
            key: const ValueKey('guest-name'),
            controller: name,
            autofocus: true,
            maxLength: 40,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(labelText: 'Name', counterText: '', errorText: error),
            onSubmitted: (_) => _add(),
          ),
          if (added.isNotEmpty) ...[
            const SizedBox(height: 8),
            Wrap(spacing: 6, runSpacing: 6, children: [for (final n in added) Chip(avatar: Icon(Icons.check, size: 16, color: c.forest), label: Text(n), visualDensity: VisualDensity.compact)]),
          ],
        ]),
      ),
      actions: [
        TextButton(key: const ValueKey('guest-done'), onPressed: () => Navigator.pop(context), child: Text(added.isEmpty ? 'Cancel' : 'Done')),
        FilledButton.icon(key: const ValueKey('guest-add'), onPressed: busy ? null : _add, icon: const Icon(Icons.person_add_alt, size: 18), label: Text(added.isEmpty ? 'Add' : 'Add another')),
      ],
    );
  }
}


Future<void> _pickSharers(BuildContext context, Json g, Json item, Future<void> Function(Future<void> Function(GroupApi), {String? success}) run) async {
  final members = (g['members'] as List).cast<Map>();
  final chosen = <String>{...((item['sharedWith'] as List).isEmpty ? [item['memberId'] as String] : (item['sharedWith'] as List).cast<String>())};
  final ok = await showDialog<bool>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, set) => AlertDialog(
        title: Text('Who shares ${item['name']}?'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in members)
            CheckboxListTile(
              key: ValueKey('sharer-${m['userId']}'),
              dense: true,
              value: chosen.contains(m['userId']),
              onChanged: (v) => set(() => v == true ? chosen.add(m['userId'] as String) : chosen.remove(m['userId'])),
              title: Text(m['isYou'] == true ? 'You' : m['name'] as String),
            ),
          Text('Its cost is split evenly between the people you pick. It is never charged twice.', style: Theme.of(context).textTheme.bodySmall),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(key: const ValueKey('share-save'), onPressed: chosen.isEmpty ? null : () => Navigator.pop(context, true), child: const Text('Save')),
        ],
      ),
    ),
  );
  if (ok != true) return;
  await run((api) => api.share(g['id'] as String, item['id'] as String, chosen.toList(), g['version'] as int), success: 'Bill split updated');
}

class _SplitCard extends StatefulWidget {
  final Json g;
  final bool busy;
  final Future<void> Function(Future<void> Function(GroupApi), {String? success}) run;
  const _SplitCard({required this.g, required this.busy, required this.run});
  @override
  State<_SplitCard> createState() => _SplitCardState();
}

class _SplitCardState extends State<_SplitCard> {
  String? open;
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    final g = widget.g;
    final split = Json.from(g['split'] as Map);
    final method = split['method'] as String;
    final organizer = g['isOrganizer'] == true;
    final editable = organizer && !['ORDERED', 'CANCELED', 'EXPIRED'].contains(g['status']);
    final basis = split['basis'] as String;
    final names = {for (final m in (g['members'] as List).cast<Map>()) m['userId']: m['isYou'] == true ? 'You' : m['name']};
    return _Card(
      cardKey: const ValueKey('group-split'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(child: Text('Split bill', style: text.titleMedium?.copyWith(fontWeight: FontWeight.w800))),
          DecoratedBox(
            decoration: BoxDecoration(color: basis == 'ESTIMATE' ? c.goldBg : c.successBg, borderRadius: BorderRadius.circular(999)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              child: Text(basis == 'ESTIMATE' ? 'Estimate' : basis == 'AGREED' ? 'Agreed price' : 'Final', key: const ValueKey('split-basis'), style: text.labelSmall?.copyWith(fontWeight: FontWeight.w800, color: basis == 'ESTIMATE' ? c.charcoal : c.success)),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        SegmentedButton<String>(
          key: const ValueKey('split-method'),
          segments: const [
            ButtonSegment(value: 'BY_PERSON', label: Text('By person'), icon: Icon(Icons.person_outline)),
            ButtonSegment(value: 'EQUAL', label: Text('Equally'), icon: Icon(Icons.drag_handle)),
          ],
          selected: {method},
          onSelectionChanged: !editable || widget.busy ? null : (v) => widget.run((api) => api.setSplit(g['id'] as String, v.first, g['version'] as int)),
        ),
        if (!editable && !['ORDERED'].contains(g['status'])) Padding(padding: const EdgeInsets.only(top: 4), child: Text('The organizer chooses how to split.', style: text.bodySmall?.copyWith(color: c.muted))),
        const SizedBox(height: 8),
        for (final m in (split['members'] as List).cast<Map>()) ...[
          InkWell(
            key: ValueKey('split-${m['userId']}'),
            onTap: () => setState(() => open = open == m['userId'] ? null : m['userId'] as String),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(children: [
                CircleAvatar(radius: 14, backgroundColor: m['userId'] == split['organizerId'] ? c.gold : c.paleGreen, child: Text(((names[m['userId']] ?? m['name']) as String)[0].toUpperCase(), style: text.labelMedium?.copyWith(color: c.forest))),
                const SizedBox(width: 10),
                Expanded(child: Text('${names[m['userId']] ?? m['name']}${m['userId'] == split['organizerId'] ? ' · pays the order' : ''}', maxLines: 1, overflow: TextOverflow.ellipsis)),
                Text(rupees(m['sharePaise'] as int), style: text.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                Icon(open == m['userId'] ? Icons.expand_less : Icons.expand_more, size: 18, color: c.muted),
              ]),
            ),
          ),
          if (open == m['userId'])
            Padding(
              padding: const EdgeInsets.fromLTRB(38, 0, 4, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                for (final it in (m['items'] as List? ?? []).cast<Map>())
                  _row(context, '${it['name']}${(it['sharedBetween'] as int) > 1 ? ' (1/${it['sharedBetween']})' : ''}', rupees(it['portionPaise'] as int)),
                if (method == 'EQUAL') _row(context, 'Equal share of food', rupees(m['foodPaise'] as int)),
                _row(context, 'Fees and taxes', rupees(m['feesPaise'] as int)),
                if ((m['discountPaise'] as int) != 0) _row(context, 'Discount', '−${rupees(m['discountPaise'] as int)}', color: c.success),
              ]),
            ),
        ],
        const Divider(),
        _row(context, 'Group total', rupees(split['payablePaise'] as int), bold: true),
        Text('Shares add up to ${rupees(split['sumPaise'] as int)}. ${split['note']}', key: const ValueKey('split-note'), style: text.bodySmall?.copyWith(color: c.muted)),
      ]),
    );
  }
}
