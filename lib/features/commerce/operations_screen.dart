import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'commerce_repository.dart';
import 'commerce_widgets.dart';
import 'live_orders.dart';

const actionLabels = {
  'accept': 'Accept',
  'reject': 'Reject',
  'start-preparing': 'Start preparing',
  'ready': 'Mark ready',
  'pickup': 'Confirm pickup',
  'out-for-delivery': 'Out for delivery',
  'deliver': 'Confirm delivered',
};

class OperationsScreen extends ConsumerStatefulWidget {
  final String scope;
  final String? orderId;
  const OperationsScreen({super.key, required this.scope, this.orderId});
  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  int page = 1;
  String get path =>
      'operations/${widget.scope}/orders${widget.orderId == null ? '?page=$page' : '/${widget.orderId}'}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        widget.scope == 'dispatch'
            ? 'Delivery dispatch'
            : widget.scope == 'delivery'
            ? 'Your deliveries'
            : 'Kitchen operations',
      ),
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: LiveOrderBar(path: path, orderId: widget.orderId),
        ),
        Expanded(
          child: ref
              .watch(commerceReadProvider(path))
              .when(
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => CommerceFailure(
                  e,
                  () => ref.invalidate(commerceReadProvider(path)),
                ),
                data: (raw) {
                  final items = widget.orderId != null
                      ? [Json.from(raw)]
                      : [for (final o in raw['items']) Json.from(o)];
                  return ListView(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                    children: [
                      if (items.isEmpty)
                        const Padding(
                          padding: EdgeInsets.all(32),
                          child: Text(
                            'No orders to show. Refresh to check for updates.',
                          ),
                        ),
                      for (final o in items)
                        OperationCard(
                          key: ValueKey(o['id']),
                          order: o,
                          scope: widget.scope,
                          onChanged: () {
                            ref.invalidate(commerceReadProvider(path));
                            ref.invalidate(
                              commerceReadProvider(
                                'operations/dispatch/riders',
                              ),
                            );
                          },
                        ),
                      if (widget.orderId == null)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            TextButton(
                              onPressed: page > 1
                                  ? () => setState(() => page--)
                                  : null,
                              child: const Text('Previous'),
                            ),
                            Text('Page $page'),
                            TextButton(
                              onPressed: page * 20 < (raw['total'] as int)
                                  ? () => setState(() => page++)
                                  : null,
                              child: const Text('Next'),
                            ),
                          ],
                        ),
                    ],
                  );
                },
              ),
        ),
      ],
    ),
  );
}

class OperationCard extends ConsumerStatefulWidget {
  final Json order;
  final String scope;
  final VoidCallback onChanged;
  const OperationCard({
    super.key,
    required this.order,
    required this.scope,
    required this.onChanged,
  });
  @override
  ConsumerState<OperationCard> createState() => _OperationCardState();
}

class _OperationCardState extends ConsumerState<OperationCard> {
  bool busy = false;
  String? error;
  Future<void> act(String action, {String? riderId}) async {
    if (busy) return;
    String? reason;
    if (action == 'reject') {
      final controller = TextEditingController();
      reason = await showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('Why is this order being declined?'),
          content: TextField(
            controller: controller,
            maxLength: 300,
            decoration: const InputDecoration(
              labelText: 'Reason (at least 5 characters)',
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Keep order'),
            ),
            FilledButton(
              onPressed: () {
                if (controller.text.trim().length >= 5) {
                  Navigator.pop(context, controller.text.trim());
                }
              },
              child: const Text('Reject order'),
            ),
          ],
        ),
      );
      controller.dispose();
      if (reason == null || !mounted) return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(commerceRepositoryProvider).request(
        'POST',
        'operations/${widget.scope}/orders/${widget.order['id']}/$action',
        {
          'expectedVersion': widget.order['version'],
          'reason': ?reason,
          'riderId': ?riderId,
        },
      );
      if (mounted) widget.onChanged();
    } catch (e) {
      if (mounted) setState(() => error = commerceError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final o = widget.order,
        actions = (o['availableActions'] as List? ?? []).cast<String>();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              o['restaurantName'],
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 6),
            Text(shortOrderRef(o['orderNumber'])),
            Text(
              formatOrderTime(o['createdAt']),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OrderStatusBadge(o['status']),
                PaymentTag(o['paymentStatus']),
              ],
            ),
            const SizedBox(height: 10),
            for (final item in o['items'])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  [
                    "${item['quantity']} × ${item['name']}",
                    if (item['variantSnapshot'] != null)
                      item['variantSnapshot']['name'],
                    for (final a in item['addOns']) a['name'],
                  ].join(' · '),
                ),
              ),
            Text(
              'Final payable · ₹${((o['finalPayablePaise'] as int) / 100).toStringAsFixed(2)}',
              style: Theme.of(context).textTheme.titleSmall,
            ),
            if (widget.scope == 'restaurant' &&
                o['status'] == 'PENDING_RESTAURANT' &&
                o['paymentEligible'] != true)
              const Padding(
                padding: EdgeInsets.only(top: 8),
                child: Text('Payment is not eligible for acceptance.'),
              ),
            if (widget.scope == 'delivery' &&
                o['deliveryAddressSnapshot'] is Map) ...[
              const Divider(),
              if (o['restaurant'] is Map)
                Text('Pickup: ${o['restaurant']['address']}'),
              const Text('Delivery destination'),
              Text(
                [
                  o['deliveryAddressSnapshot']['recipientName'],
                  o['deliveryAddressSnapshot']['contactNumber'],
                  o['deliveryAddressSnapshot']['addressLine1'],
                  o['deliveryAddressSnapshot']['addressLine2'],
                  o['deliveryAddressSnapshot']['landmark'],
                  o['deliveryAddressSnapshot']['localityName'],
                  o['deliveryAddressSnapshot']['postalCode'],
                ].where((v) => v != null && v != '').join('\n'),
              ),
            ],
            if (widget.scope == 'dispatch' &&
                o['status'] == 'READY_FOR_PICKUP' &&
                o['assignment'] == null)
              ref
                  .watch(commerceReadProvider('operations/dispatch/riders'))
                  .when(
                    loading: () => const LinearProgressIndicator(),
                    error: (e, _) => Text(commerceError(e)),
                    data: (raw) => Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const SizedBox(height: 10),
                        const Text('Assign an available delivery partner'),
                        if ((raw as List).isEmpty)
                          const Text('No available delivery partners.'),
                        for (final rider in raw)
                          OutlinedButton(
                            onPressed: busy
                                ? null
                                : () => act('assign', riderId: rider['id']),
                            child: Text('Assign ${rider['displayName']}'),
                          ),
                      ],
                    ),
                  ),
            if (o['assignment'] != null)
              Text(
                'Assigned to ${o['assignment']['rider']?['displayName'] ?? 'delivery partner'} · ${formatOrderTime(o['assignment']['assignedAt'])}',
              ),
            if (error != null)
              Text(
                error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final action in actions)
                  FilledButton(
                    onPressed: busy ? null : () => act(action),
                    child: Text(actionLabels[action] ?? 'Update'),
                  ),
              ],
            ),
            if (busy) const LinearProgressIndicator(),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Order timeline'),
              children: [OrderTimeline(order: o)],
            ),
          ],
        ),
      ),
    );
  }
}
