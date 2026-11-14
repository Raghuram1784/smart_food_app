import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog.dart';
import '../commerce/commerce_repository.dart';
import '../commerce/commerce_widgets.dart';
import '../commerce/live_orders.dart';
import '../commerce/operations_screen.dart';
import 'rider_presence_provider.dart';

/// Delivery partner workspace. No GPS, no map: an Online/Offline toggle,
/// persisted delivery requests (Accept / Decline) and the rider's own orders.
class RiderDashboardScreen extends ConsumerStatefulWidget {
  final String? tab;
  final String? orderId;
  const RiderDashboardScreen({super.key, this.tab, this.orderId});

  @override
  ConsumerState<RiderDashboardScreen> createState() => _RiderDashboardScreenState();
}

class _RiderDashboardScreenState extends ConsumerState<RiderDashboardScreen> {
  late String _activeTab;
  int _page = 1;
  Timer? _poll;
  final _announced = <String>{};
  bool _dialogOpen = false;
  final _responding = <String>{};

  @override
  void initState() {
    super.initState();
    _activeTab = _normalizeTab(widget.tab);
    // Safety net besides Socket.IO: re-read persisted requests periodically while visible.
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted && ref.read(riderPresenceProvider).isOnline) ref.invalidate(riderOffersProvider);
    });
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant RiderDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab && widget.tab != null) {
      setState(() => _activeTab = _normalizeTab(widget.tab));
    }
  }

  String _normalizeTab(String? raw) => switch (raw) {
    'active' || 'transit' => 'transit',
    'history' => 'history',
    'all' => 'all',
    _ => 'assigned',
  };

  String get _orderPath =>
      'operations/delivery/orders${widget.orderId == null ? '?page=$_page' : '/${widget.orderId}'}';

  void _refreshAll() {
    ref.invalidate(commerceReadProvider(_orderPath));
    ref.invalidate(riderOffersProvider);
    ref.read(riderPresenceProvider.notifier).refresh();
  }

  Future<void> _respond(Json offer, bool accept) async {
    final id = offer['id'] as String;
    if (_responding.contains(id)) return;
    setState(() => _responding.add(id));
    final messenger = ScaffoldMessenger.of(context);
    try {
      await ref.read(commerceRepositoryProvider).request(
        'POST',
        'operations/delivery/offers/$id/${accept ? 'accept' : 'decline'}',
      );
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            content: Text(
              accept
                  ? 'Delivery accepted: ${offer['orderNumber']}. Pick it up from ${offer['restaurantName']}.'
                  : 'Request declined.',
            ),
          ),
        );
      if (accept && mounted) setState(() => _activeTab = 'assigned');
    } catch (e) {
      messenger
        ..hideCurrentSnackBar()
        ..showSnackBar(SnackBar(content: Text(commerceError(e))));
    } finally {
      if (mounted) {
        setState(() => _responding.remove(id));
        _refreshAll();
      }
    }
  }

  /// Show a popup for the first request this screen hasn't announced yet.
  void _announce(List<Json> offers) {
    if (_dialogOpen || !mounted) return;
    final fresh = offers.where((o) => !_announced.contains(o['id'])).toList();
    if (fresh.isEmpty) return;
    for (final o in fresh) {
      _announced.add(o['id'] as String);
    }
    final offer = fresh.first;
    _dialogOpen = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        _dialogOpen = false;
        return;
      }
      final choice = await showDialog<bool>(
        context: context,
        builder: (_) => _OfferDialog(offer: offer),
      );
      _dialogOpen = false;
      if (choice != null && mounted) await _respond(offer, choice);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final presence = ref.watch(riderPresenceProvider);

    ref.listen(liveOrdersProvider, (_, next) {
      final e = next.asData?.value;
      if (e == null) return;
      if (e.offersChanged || e.reconcile || e.eventType == 'RIDER_ASSIGNED') {
        ref.invalidate(riderOffersProvider);
        ref.read(riderPresenceProvider.notifier).refresh();
      }
    });
    ref.listen(riderOffersProvider, (_, next) {
      final offers = next.asData?.value;
      if (offers != null) _announce(offers);
    });

    final offers = ref.watch(riderOffersProvider);

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Delivery Partner', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            Text('Your deliveries', style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
        actions: [
          IconButton(tooltip: 'Refresh', icon: const Icon(Icons.refresh), onPressed: _refreshAll),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: () async => _refreshAll(),
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            LiveOrderBar(path: _orderPath, orderId: widget.orderId),
            const SizedBox(height: 10),
            _AvailabilityCard(
              presence: presence,
              onToggle: () => ref.read(riderPresenceProvider.notifier).setOnline(!presence.isOnline),
            ),
            if (presence.isOnline && !presence.onDelivery) ...[
              const SizedBox(height: 18),
              Text('New delivery requests', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              offers.when(
                loading: () => const Padding(padding: EdgeInsets.all(16), child: Center(child: CircularProgressIndicator())),
                error: (e, _) => CommerceFailure(e, () => ref.invalidate(riderOffersProvider)),
                data: (list) => list.isEmpty
                    ? const _Hint(icon: Icons.notifications_none, text: 'Waiting for new delivery requests. They appear here automatically when a restaurant marks an order ready.')
                    : Column(
                        children: [
                          for (final o in list)
                            _OfferCard(
                              key: ValueKey(o['id']),
                              offer: o,
                              busy: _responding.contains(o['id']),
                              onAccept: () => _respond(o, true),
                              onDecline: () => _respond(o, false),
                            ),
                        ],
                      ),
              ),
            ],
            const SizedBox(height: 18),
            ref.watch(commerceReadProvider(_orderPath)).when(
              loading: () => const Padding(padding: EdgeInsets.symmetric(vertical: 32), child: Center(child: CircularProgressIndicator())),
              error: (e, _) => CommerceFailure(e, () => ref.invalidate(commerceReadProvider(_orderPath))),
              data: (raw) => _orders(theme, presence, raw),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orders(ThemeData theme, RiderPresenceState presence, dynamic raw) {
    final all = widget.orderId != null
        ? [Json.from(raw as Map)]
        : [for (final o in (raw['items'] as List? ?? [])) Json.from(o as Map)];
    final assigned = all.where((o) => o['status'] == 'READY_FOR_PICKUP').toList();
    final transit = all.where((o) => o['status'] == 'PICKED_UP' || o['status'] == 'OUT_FOR_DELIVERY').toList();
    final history = all.where((o) => o['status'] == 'DELIVERED').toList();
    final shown = switch (_activeTab) {
      'transit' => transit,
      'history' => history,
      'all' => all,
      _ => assigned,
    };
    final total = widget.orderId != null ? 1 : (raw['total'] as int? ?? all.length);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final (key, label) in [
                ('assigned', 'Assigned (${assigned.length})'),
                ('transit', 'In Transit (${transit.length})'),
                ('history', 'History (${history.length})'),
                ('all', 'All (${all.length})'),
              ])
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: ChoiceChip(
                    label: Text(label),
                    selected: _activeTab == key,
                    onSelected: (_) => setState(() => _activeTab = key),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (shown.isEmpty)
          _Hint(
            icon: Icons.two_wheeler_outlined,
            text: switch (_activeTab) {
              'transit' => 'No orders currently in transit.',
              'history' => 'No completed deliveries yet.',
              'all' => 'No delivery orders yet.',
              _ => presence.isOnline ? 'No assigned deliveries. Accept a request above to start.' : 'Go Online to receive delivery requests.',
            },
          )
        else
          for (final order in shown) ...[
            OperationCard(
              key: ValueKey(order['id']),
              order: order,
              scope: 'delivery',
              onChanged: _refreshAll,
            ),
            const SizedBox(height: 10),
          ],
        if (widget.orderId == null && (total > 20 || _page > 1))
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              TextButton(onPressed: _page > 1 ? () => setState(() => _page--) : null, child: const Text('Previous')),
              Text('Page $_page of ${(total / 20).ceil().clamp(1, 9999)}', style: theme.textTheme.bodySmall),
              TextButton(onPressed: _page * 20 < total ? () => setState(() => _page++) : null, child: const Text('Next')),
            ],
          ),
      ],
    );
  }
}

class _AvailabilityCard extends StatelessWidget {
  final RiderPresenceState presence;
  final VoidCallback onToggle;
  const _AvailabilityCard({required this.presence, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final online = presence.isOnline;
    final (label, sub, color, icon) = !online
        ? ('Offline', 'Go Online to receive delivery requests', scheme.outline, Icons.power_settings_new_rounded)
        : presence.onDelivery
            ? ('On a delivery', 'Finish your current delivery to receive new requests', scheme.primary, Icons.delivery_dining_rounded)
            : ('Online & available', 'You will receive new delivery requests', Colors.green.shade700, Icons.check_circle_rounded);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: online ? color.withValues(alpha: 0.5) : scheme.outlineVariant, width: online ? 1.5 : 1),
      ),
      child: Column(
        children: [
          Row(
            children: [
              CircleAvatar(backgroundColor: color.withValues(alpha: 0.15), child: Icon(icon, color: color)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: online ? color : null)),
                    Text(sub, style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
                  ],
                ),
              ),
            ],
          ),
          if (presence.error != null) ...[
            const SizedBox(height: 10),
            Text(presence.error!, style: theme.textTheme.bodySmall?.copyWith(color: scheme.error)),
          ],
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            height: 48,
            child: online
                ? OutlinedButton.icon(
                    onPressed: presence.busy ? null : onToggle,
                    icon: const Icon(Icons.power_settings_new),
                    label: const Text('Go Offline', style: TextStyle(fontWeight: FontWeight.bold)),
                  )
                : FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: Colors.green.shade700, foregroundColor: Colors.white),
                    onPressed: presence.busy ? null : onToggle,
                    icon: presence.busy
                        ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.flash_on_rounded),
                    label: const Text('Go Online', style: TextStyle(fontWeight: FontWeight.bold)),
                  ),
          ),
        ],
      ),
    );
  }
}

String _itemsSummary(Json offer) => [
  for (final i in (offer['items'] as List? ?? const []))
    '${(i as Map)['quantity']} × ${i['name']}',
].join(', ');

class _OfferCard extends StatelessWidget {
  final Json offer;
  final bool busy;
  final VoidCallback onAccept;
  final VoidCallback onDecline;
  const _OfferCard({super.key, required this.offer, required this.busy, required this.onAccept, required this.onDecline});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: scheme.primary.withValues(alpha: 0.4))),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Icon(Icons.storefront, color: scheme.primary),
              const SizedBox(width: 8),
              Expanded(child: Text(offer['restaurantName'] as String? ?? 'Restaurant', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
            ]),
            const SizedBox(height: 6),
            Text('Order ${offer['orderNumber']}', style: theme.textTheme.labelLarge),
            if (offer['pickupAddress'] != null) Text('Pickup: ${offer['pickupAddress']}', style: theme.textTheme.bodySmall),
            if (offer['dropArea'] != null) Text('Drop area: ${offer['dropArea']}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 4),
            Text(_itemsSummary(offer), style: theme.textTheme.bodySmall),
            if (offer['orderTotalPaise'] is int) Text('Order value ₹${formatPaise(offer['orderTotalPaise'] as int)}', style: theme.textTheme.bodySmall),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(child: OutlinedButton(onPressed: busy ? null : onDecline, child: const Text('Decline'))),
                const SizedBox(width: 10),
                Expanded(
                  flex: 2,
                  child: FilledButton.icon(
                    onPressed: busy ? null : onAccept,
                    icon: busy ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check),
                    label: const Text('Accept Delivery'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OfferDialog extends StatelessWidget {
  final Json offer;
  const _OfferDialog({required this.offer});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      icon: const Icon(Icons.delivery_dining, size: 36),
      title: const Text('New Delivery Request'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Restaurant: ${offer['restaurantName']}', style: theme.textTheme.titleSmall),
          const SizedBox(height: 4),
          Text('Order: ${offer['orderNumber']}'),
          if (offer['pickupAddress'] != null) Text('Pickup: ${offer['pickupAddress']}'),
          if (offer['dropArea'] != null) Text('Drop area: ${offer['dropArea']}'),
          const SizedBox(height: 6),
          Text('Items: ${_itemsSummary(offer)}'),
        ],
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Decline')),
        FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Accept Delivery')),
      ],
    );
  }
}

class _Hint extends StatelessWidget {
  final IconData icon;
  final String text;
  const _Hint({required this.icon, required this.text});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
      child: Column(
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.outline),
          const SizedBox(height: 10),
          Text(text, textAlign: TextAlign.center, style: theme.textTheme.bodySmall),
        ],
      ),
    );
  }
}
