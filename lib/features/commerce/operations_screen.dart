import '../scheduling/schedule_widgets.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
  'arrived': "I've Arrived",
  'complete-handover': 'Confirm delivery (PIN)',
  'deliver': 'Confirm delivered',
};

String cleanItemPortion(String name, String? variant) {
  if (variant == null || variant.isEmpty) return name;
  return name
      .replaceAll(RegExp(r'\s*\(\d+\s*pc\)', caseSensitive: false), '')
      .trim();
}

class OperationsScreen extends ConsumerStatefulWidget {
  final String scope;
  final String? orderId;
  final String? tab;
  const OperationsScreen({
    super.key,
    required this.scope,
    this.orderId,
    this.tab,
  });
  @override
  ConsumerState<OperationsScreen> createState() => _OperationsScreenState();
}

class _OperationsScreenState extends ConsumerState<OperationsScreen> {
  int page = 1;
  late String activeTab;

  @override
  void initState() {
    super.initState();
    activeTab = widget.tab ?? 'all';
  }

  @override
  void didUpdateWidget(covariant OperationsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.tab != oldWidget.tab && widget.tab != null) {
      setState(() => activeTab = widget.tab!);
    }
  }

  String get path =>
      'operations/${widget.scope}/orders${widget.orderId == null ? '?page=$page' : '/${widget.orderId}'}';
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      leading: Navigator.of(context).canPop()
          ? IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => Navigator.of(context).maybePop(),
            )
          : null,
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
    if (action == 'complete-handover' || action == 'deliver') {
      await showDialog<void>(
        context: context,
        barrierDismissible: !busy,
        builder: (context) => _HandoverPinDialog(
          order: widget.order,
          onSuccess: widget.onChanged,
        ),
      );
      return;
    }
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
      final result = await ref.read(commerceRepositoryProvider).request(
        'POST',
        'operations/${widget.scope}/orders/${widget.order['id']}/$action',
        {
          'expectedVersion': widget.order['version'],
          'reason': ?reason,
          'riderId': ?riderId,
        },
      );
      if (action == 'arrived' && mounted) {
        final reissued = result is Map && result['reissued'] == true;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            SnackBar(
              content: Text(
                reissued
                    ? "The previous code expired. A new OTP was sent to the customer's app — ask them for it."
                    : 'Ask the customer for the 6-digit OTP shown in their app.',
              ),
            ),
          );
      }
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
            ScheduleCard(order: o),
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
                    "${item['quantity']} × ${cleanItemPortion(item['name'] as String, item['variantSnapshot']?['name'] as String?)}",
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

class _HandoverPinDialog extends ConsumerStatefulWidget {
  final Json order;
  final VoidCallback onSuccess;

  const _HandoverPinDialog({required this.order, required this.onSuccess});

  @override
  ConsumerState<_HandoverPinDialog> createState() => _HandoverPinDialogState();
}

class _HandoverPinDialogState extends ConsumerState<_HandoverPinDialog> {
  final _pinController = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pinController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final pin = _pinController.text.trim();
    if (pin.length != 6) return;

    setState(() {
      _busy = true;
      _error = null;
    });

    try {
      await ref.read(commerceRepositoryProvider).request(
        'POST',
        'operations/delivery/orders/${widget.order['id']}/complete-handover',
        {'pin': pin, 'expectedVersion': widget.order['version']},
      );
      if (mounted) {
        Navigator.pop(context);
        widget.onSuccess();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Handover verified! Delivery confirmed.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = commerceError(e);
        });
        widget.onSuccess();
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final order = widget.order;
    final addr = order['deliveryAddressSnapshot'] as Map?;
    final recipientName = addr?['recipientName'] as String? ?? 'Customer';

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.pin_outlined, color: scheme.primary),
          const SizedBox(width: 8),
          const Expanded(child: Text('Verify delivery PIN')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${shortOrderRef(order['orderNumber'])} · $recipientName',
              style: theme.textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Ask the customer for the 6-digit handover PIN shown on their order tracking screen.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _pinController,
              autofocus: true,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              maxLength: 6,
              style: theme.textTheme.headlineMedium?.copyWith(
                letterSpacing: 10,
                fontWeight: FontWeight.bold,
                fontFamily: 'monospace',
                color: scheme.primary,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(6),
              ],
              decoration: InputDecoration(
                hintText: '000000',
                hintStyle: TextStyle(
                  letterSpacing: 10,
                  color: scheme.outlineVariant,
                ),
                counterText: '',
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest.withValues(
                  alpha: 0.3,
                ),
              ),
              onChanged: (_) => setState(() {}),
              onSubmitted: (_) {
                if (_pinController.text.trim().length == 6 && !_busy) {
                  _submit();
                }
              },
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: scheme.errorContainer.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(Icons.error_outline, size: 16, color: scheme.error),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: scheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (_busy) ...[
              const SizedBox(height: 14),
              const Center(
                child: SizedBox(
                  height: 20,
                  width: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: (_busy || _pinController.text.trim().length != 6)
              ? null
              : _submit,
          child: const Text('Confirm delivery'),
        ),
      ],
    );
  }
}
