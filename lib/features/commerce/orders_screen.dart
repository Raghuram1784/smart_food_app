import '../tracking/tracking_api.dart';
import '../scheduling/schedule_widgets.dart';
import 'customer_handover_card.dart';
import 'live_orders.dart';
import 'payment_panel.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../catalog/catalog.dart';
import '../../shared/components.dart';
import 'commerce_repository.dart';
import 'commerce_widgets.dart';

class OrdersScreen extends ConsumerStatefulWidget {
  final String? restaurantId;
  const OrdersScreen({super.key, this.restaurantId});
  @override
  ConsumerState<OrdersScreen> createState() => _OrdersScreenState();
}

class _OrdersScreenState extends ConsumerState<OrdersScreen> {
  int page = 1;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final owner = widget.restaurantId != null;
    final path =
        '${owner ? 'restaurants/${widget.restaurantId}/orders' : 'orders'}?page=$page&limit=10';

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) ScaffoldMessenger.of(context).removeCurrentSnackBar();
    });

    return Scaffold(
      appBar: AppBar(
        leading: !owner
            ? (Navigator.of(context).canPop()
                  ? IconButton(
                      tooltip: 'Back',
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        if (Navigator.of(context).canPop()) {
                          Navigator.of(context).pop();
                        } else {
                          context.go('/');
                        }
                      },
                    )
                  : IconButton(
                      tooltip: 'Discover',
                      icon: const Icon(Icons.home_outlined),
                      onPressed: () => context.go('/'),
                    ))
            : null,
        title: Text(owner ? 'Incoming orders' : 'Your orders'),
        actions: [
          IconButton(
            tooltip: 'Refresh orders',
            onPressed: () => ref.invalidate(commerceReadProvider(path)),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ref
          .watch(commerceReadProvider(path))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => CommerceFailure(
              e,
              () => ref.invalidate(commerceReadProvider(path)),
            ),
            data: (data) {
              final items = (data['items'] as List).cast<Map>();
              final total = (data['total'] as int?) ?? items.length;
              final pendingCount =
                  (data['pendingCount'] as int?) ??
                  items
                      .where((o) => o['status'] == 'PENDING_RESTAURANT')
                      .length;

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
                children: [
                  LiveOrderBar(path: path),
                  if (owner) ...[
                    _InboxSummaryBanner(
                      pendingCount: pendingCount,
                      totalCount: total,
                    ),
                    const SizedBox(height: 12),
                  ] else if (total > 0) ...[
                    Text(
                      '$total recorded ${total == 1 ? 'order' : 'orders'}',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 10),
                  ],
                  if (items.isEmpty) ...[
                    const SizedBox(height: 56),
                    Icon(
                      Icons.receipt_long_outlined,
                      size: 52,
                      color: scheme.primary,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      owner
                          ? 'No incoming orders yet.'
                          : 'Your first order awaits.',
                      style: theme.textTheme.headlineSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      owner
                          ? 'Recorded customer orders for this kitchen will appear here.'
                          : 'Only real persisted orders appear here.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                    if (!owner) ...[
                      const SizedBox(height: 16),
                      Center(
                        child: FilledButton.tonal(
                          onPressed: () => context.go('/'),
                          child: const Text('Explore meals'),
                        ),
                      ),
                    ],
                  ] else ...[
                    for (final order in items) ...[
                      _OrderSummaryCard(
                        order: Json.from(order),
                        owner: owner,
                        onViewDetails: () {
                          if (owner) {
                            context.push(
                              '/inbox/${widget.restaurantId}/orders/${order['id']}',
                              extra: Json.from(order),
                            );
                          } else {
                            context.push('/orders/${order['id']}');
                          }
                        },
                      ),
                      const SizedBox(height: 10),
                    ],
                    if (total > 10 || page > 1) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton(
                            onPressed: page > 1
                                ? () => setState(() => page--)
                                : null,
                            child: const Text('Newer'),
                          ),
                          Text(
                            'Page $page of ${((total - 1) ~/ 10) + 1}',
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton(
                            onPressed: page * 10 < total
                                ? () => setState(() => page++)
                                : null,
                            child: const Text('Older'),
                          ),
                        ],
                      ),
                    ],
                  ],
                ],
              );
            },
          ),
    );
  }
}

class _InboxSummaryBanner extends StatelessWidget {
  final int pendingCount;
  final int totalCount;
  const _InboxSummaryBanner({
    required this.pendingCount,
    required this.totalCount,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: culinary?.pistachio ?? scheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Text(
                  '$pendingCount pending',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSecondaryContainer,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$totalCount total recorded',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Open an order to manage acceptance and kitchen preparation.',
            style: theme.textTheme.bodySmall?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _OrderSummaryCard extends StatelessWidget {
  final Json order;
  final bool owner;
  final VoidCallback onViewDetails;
  const _OrderSummaryCard({
    required this.order,
    required this.owner,
    required this.onViewDetails,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final lines = (order['items'] as List).cast<Map>();
    final unitCount = lines.fold<int>(
      0,
      (sum, line) => sum + (line['quantity'] as int),
    );
    final summaryText = lines
        .map((line) {
          final v =
              (line['variantSnapshot']?['name'] ?? line['variant']?['name'])
                  as String?;
          final raw = line['name'] as String;
          if (v != null && v.isNotEmpty) {
            final clean = raw
                .replaceAll(
                  RegExp(r'\s*\(\d+\s*pc\)', caseSensitive: false),
                  '',
                )
                .trim();
            return '${line['quantity']} × $clean ($v)';
          }
          return '${line['quantity']} × $raw';
        })
        .join(', ');
    final orderNumber = order['orderNumber'] as String;
    final refShort = shortOrderRef(orderNumber);

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onViewDetails,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          owner ? refShort : order['restaurantName'] as String,
                          style: theme.textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          owner
                              ? '${order['restaurantName']} · ${formatOrderTime(order['createdAt'] as String)}'
                              : '$refShort · ${formatOrderTime(order['createdAt'] as String)}',
                          style: theme.textTheme.bodySmall,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 10),
                  Text(
                    '₹${formatPaise(order['finalPayablePaise'] as int)}',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: scheme.primary,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$unitCount ${unitCount == 1 ? 'item' : 'items'} · $summaryText',
                style: theme.textTheme.bodyMedium,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              Divider(height: 1, color: scheme.outlineVariant),
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        OrderStatusBadge(order['status'] as String),
                        ScheduleCard(order: order, compact: true),
                        PaymentTag(
                          order['paymentStatus'] as String,
                          concise: true,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (!owner && isTrackable(order)) ...[
                    TrackOrderButton(orderId: order['id'] as String, compact: true),
                    const SizedBox(width: 4),
                  ],
                  TextButton(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: onViewDetails,
                    child: const Text('View details'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class OrderDetailScreen extends ConsumerWidget {
  final String id;
  final bool placed;
  const OrderDetailScreen({super.key, required this.id, this.placed = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      ScaffoldMessenger.of(context).removeCurrentSnackBar();
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(placed ? 'Order confirmation' : 'Order details'),
        leading: IconButton(
          tooltip: 'Back',
          onPressed: () {
            if (Navigator.of(context).canPop()) {
              Navigator.of(context).pop();
            } else {
              context.go(placed ? '/orders' : '/');
            }
          },
          icon: const Icon(Icons.arrow_back),
        ),
      ),
      body: ref
          .watch(commerceReadProvider('orders/$id'))
          .when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => CommerceFailure(
              e,
              () => ref.invalidate(commerceReadProvider('orders/$id')),
            ),
            data: (raw) {
              final o = Json.from(raw as Map);
              final lines = (o['items'] as List).cast<Map>();
              final addr = Json.from(o['deliveryAddressSnapshot'] as Map);

              final payment = o['paymentMethod'] == 'RAZORPAY_TEST'
                  ? PaymentPanel(key: ValueKey(id), orderId: id)
                  : const SizedBox.shrink();
              if (placed) {
                return ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
                  children: [
                    Center(
                      child: Container(
                        width: 60,
                        height: 60,
                        decoration: BoxDecoration(
                          color:
                              culinary?.pistachio ?? scheme.secondaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 32,
                          color: scheme.secondary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      'Your order has been recorded',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.headlineMedium,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      o['restaurantName'] as String,
                      textAlign: TextAlign.center,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          shortOrderRef(o['orderNumber'] as String),
                          style: theme.textTheme.bodySmall,
                        ),
                        CopyOrderRefButton(o['orderNumber'] as String),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Material(
                      color: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    'Final payable',
                                    style: theme.textTheme.titleMedium,
                                  ),
                                ),
                                Text(
                                  '₹${formatPaise(o['finalPayablePaise'] as int)}',
                                  style: theme.textTheme.headlineMedium,
                                ),
                              ],
                            ),
                            const Divider(height: 22),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  Text(
                                    'Order status',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  OrderStatusBadge(o['status'] as String),
                                ],
                              ),
                            ),
                            const SizedBox(height: 10),
                            SizedBox(
                              width: double.infinity,
                              child: Wrap(
                                alignment: WrapAlignment.spaceBetween,
                                crossAxisAlignment: WrapCrossAlignment.center,
                                spacing: 8,
                                runSpacing: 6,
                                children: [
                                  Text(
                                    'Payment',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                  PaymentTag(o['paymentStatus'] as String),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Material(
                      color: scheme.surfaceContainer,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                        side: BorderSide(color: scheme.outlineVariant),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Items summary',
                              style: theme.textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            for (final line in lines) ...[
                              _OrderLineRow(
                                line: Json.from(line),
                                showPhoto: false,
                              ),
                              const SizedBox(height: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                    payment,
                    const SizedBox(height: 18),
                    FilledButton(
                      onPressed: () => context.push('/orders/${o['id']}'),
                      child: const Text('View order details'),
                    ),
                    const SizedBox(height: 8),
                    OutlinedButton(
                      onPressed: () => context.go('/'),
                      child: const Text('Back to discovery'),
                    ),
                    TextButton(
                      onPressed: () => context.go('/orders'),
                      child: const Text('View order history'),
                    ),
                    ScheduleCard(order: o),
                    ScheduledCancelButton(order: o),
                    LiveOrderBar(path: 'orders/$id', orderId: id),
                  ],
                );
              }

              return ListView(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
                children: [
                  LiveOrderBar(path: 'orders/$id', orderId: id),
                  if (isTrackable(o))
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: TrackOrderButton(orderId: id),
                    ),
                  ScheduleCard(order: o),
                  ScheduledCancelButton(order: o),
                  OrderTimeline(order: o),
                  CustomerHandoverCard(
                    order: o,
                    onHandoverChanged: () =>
                        ref.invalidate(commerceReadProvider('orders/$id')),
                  ),
                  _OrderReferenceCard(order: o),
                  payment,
                  const SizedBox(height: 12),
                  _OrderItemsCard(lines: lines),
                  const SizedBox(height: 12),
                  OrderBill(o, title: 'Pricing breakdown'),
                  const SizedBox(height: 12),
                  Material(
                    color: scheme.surfaceContainer,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Delivery address',
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${addr['recipientName']} · ${addr['contactNumber'] ?? ''}'
                                .trim(),
                            style: theme.textTheme.labelLarge,
                          ),
                          Text(
                            [
                              addr['addressLine1'],
                              if ((addr['addressLine2'] as String?)
                                      ?.isNotEmpty ==
                                  true)
                                addr['addressLine2'],
                              '${addr['localityName']} ${addr['postalCode']}',
                            ].join('\n'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.go('/orders'),
                    child: const Text('View order history'),
                  ),
                  TextButton(
                    onPressed: () => context.go('/'),
                    child: const Text('Back to discovery'),
                  ),
                ],
              );
            },
          ),
    );
  }
}

class OwnerOrderDetailScreen extends ConsumerWidget {
  final String restaurantId;
  final String orderId;
  final Json? initialOrder;
  const OwnerOrderDetailScreen({
    super.key,
    required this.restaurantId,
    required this.orderId,
    this.initialOrder,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = 'restaurants/$restaurantId/orders?page=1&limit=30';
    final inboxAsync = ref.watch(commerceReadProvider(path));
    final items =
        ((inboxAsync.asData?.value as Map?)?['items'] as List? ?? const [])
            .whereType<Map>()
            .toList();

    final matched =
        items.where((o) => o['id'] == orderId).firstOrNull ?? initialOrder;

    return Scaffold(
      appBar: AppBar(title: const Text('Order detail')),
      body: inboxAsync.hasError && matched == null
          ? CommerceFailure(
              inboxAsync.error!,
              () => ref.invalidate(commerceReadProvider(path)),
            )
          : matched == null
          ? (inboxAsync.isLoading
                ? const Center(child: CircularProgressIndicator())
                : Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            'Order not found in this restaurant inbox.',
                            style: theme.textTheme.bodyMedium,
                          ),
                          const SizedBox(height: 10),
                          TextButton(
                            onPressed: () => context.pop(),
                            child: const Text('Back to incoming orders'),
                          ),
                        ],
                      ),
                    ),
                  ))
          : ListView(
              padding: const EdgeInsets.fromLTRB(20, 10, 20, 28),
              children: [
                ScheduleCard(order: Json.from(matched)),
                _OrderReferenceCard(order: Json.from(matched)),
                const SizedBox(height: 12),
                _OrderItemsCard(lines: (matched['items'] as List).cast<Map>()),
                const SizedBox(height: 12),
                OrderBill(Json.from(matched), title: 'Pricing breakdown'),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainer,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: scheme.outlineVariant),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.lock_outline_rounded,
                        size: 18,
                        color: scheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Use Kitchen operations to manage this order. Status changes are confirmed by the server.',
                          style: theme.textTheme.bodySmall,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OrderReferenceCard extends StatelessWidget {
  final Json order;
  const _OrderReferenceCard({required this.order});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final orderNumber = order['orderNumber'] as String;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              order['restaurantName'] as String,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: 4),
            Text(
              formatOrderTime(order['createdAt'] as String),
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Full order reference',
                        style: theme.textTheme.labelSmall,
                      ),
                      SelectableText(
                        orderNumber,
                        style: theme.textTheme.labelLarge,
                      ),
                    ],
                  ),
                ),
                CopyOrderRefButton(orderNumber),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OrderStatusBadge(order['status'] as String),
                PaymentTag(order['paymentStatus'] as String),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _OrderItemsCard extends StatelessWidget {
  final List<Map> lines;
  const _OrderItemsCard({required this.lines});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Ordered items', style: theme.textTheme.titleMedium),
            const SizedBox(height: 10),
            for (var i = 0; i < lines.length; i++) ...[
              _OrderLineRow(line: Json.from(lines[i])),
              if (i < lines.length - 1) const Divider(height: 18),
            ],
          ],
        ),
      ),
    );
  }
}

class _OrderLineRow extends StatelessWidget {
  final Json line;
  final bool showPhoto;
  const _OrderLineRow({required this.line, this.showPhoto = true});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final rawName = line['name'] as String;
    final variantName =
        (line['variantSnapshot']?['name'] ?? line['variant']?['name'])
            as String?;
    final cleanName = (variantName != null && variantName.isNotEmpty)
        ? rawName
              .replaceAll(RegExp(r'\s*\(\d+\s*pc\)', caseSensitive: false), '')
              .trim()
        : rawName;
    final addOns = [
      for (final a in (line['addOns'] as List? ?? const []))
        a['name'] as String,
    ];
    final photoKey = Dish.photoKeyFor(
      (line['imageKey'] as String?) ?? 'dosa',
      rawName,
    );

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showPhoto) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: FoodPhoto(photoKey, height: 48, width: 48),
          ),
          const SizedBox(width: 10),
        ],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${line['quantity']} × $cleanName',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (variantName != null && variantName.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'Option: $variantName',
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.primary,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              if (addOns.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(
                    'Add-ons: ${addOns.join(' · ')}',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '₹${formatPaise(line['lineTotalPaise'] as int)}',
          style: theme.textTheme.bodyMedium?.copyWith(
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
