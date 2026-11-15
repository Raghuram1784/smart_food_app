import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../auth/auth_provider.dart';
import '../commerce/commerce_repository.dart';
import '../commerce/commerce_widgets.dart';
import '../commerce/live_orders.dart';
import '../commerce/operations_screen.dart';

class OwnerDashboardScreen extends ConsumerStatefulWidget {
  final String? restaurantId;
  final String initialTab;

  const OwnerDashboardScreen({
    super.key,
    this.restaurantId,
    this.initialTab = 'all',
  });

  @override
  ConsumerState<OwnerDashboardScreen> createState() =>
      _OwnerDashboardScreenState();
}

class _OwnerDashboardScreenState extends ConsumerState<OwnerDashboardScreen> {
  String? _selectedRestaurantId;
  late String _activeTab;
  int _page = 1;

  @override
  void initState() {
    super.initState();
    _activeTab = widget.initialTab;
    _selectedRestaurantId = widget.restaurantId;
  }

  @override
  void didUpdateWidget(covariant OwnerDashboardScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.initialTab != oldWidget.initialTab) {
      setState(() => _activeTab = widget.initialTab);
    }
    if (widget.restaurantId != oldWidget.restaurantId) {
      setState(() {
        _selectedRestaurantId = widget.restaurantId;
        _page = 1;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final session = ref.watch(authProvider).asData?.value;
    final user = session?.user;
    final restaurants = user?.restaurants ?? [];

    if (restaurants.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text('Restaurant Kitchen')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.store_outlined, size: 54, color: scheme.outline),
                const SizedBox(height: 16),
                Text(
                  'No active restaurant memberships',
                  style: theme.textTheme.titleMedium,
                ),
                const SizedBox(height: 8),
                Text(
                  'You are authenticated as a restaurant owner, but no kitchen memberships are linked to this account.',
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () => ref.invalidate(authProvider),
                  child: const Text('Refresh permissions'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Default to first restaurant if not selected or invalid
    final activeRestaurantId =
        _selectedRestaurantId ??
        restaurants.firstWhere((r) => true, orElse: () => restaurants.first).id;
    final activeRestaurant = restaurants.firstWhere(
      (r) => r.id == activeRestaurantId,
      orElse: () => restaurants.first,
    );

    final path =
        'restaurants/$activeRestaurantId/orders?page=$_page&limit=20${_activeTab == 'scheduled' ? '&deliveryMode=SCHEDULED' : ''}';

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              activeRestaurant.name,
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
            ),
            Text(
              'Kitchen Operations',
              style: theme.textTheme.bodySmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            key: const ValueKey('owner-group-proposals'),
            tooltip: 'Group proposals',
            onPressed: () => context.push(
              '/owner/group-proposals?restaurantId=$activeRestaurantId',
            ),
            icon: const Icon(Icons.handshake_outlined),
          ),
          if (restaurants.length > 1)
            PopupMenuButton<String>(
              tooltip: 'Switch kitchen',
              icon: const Icon(Icons.storefront_outlined),
              onSelected: (id) => setState(() {
                _selectedRestaurantId = id;
                _page = 1;
              }),
              itemBuilder: (context) => [
                for (final r in restaurants)
                  PopupMenuItem(
                    value: r.id,
                    child: Row(
                      children: [
                        if (r.id == activeRestaurantId)
                          Icon(Icons.check, size: 16, color: scheme.primary)
                        else
                          const SizedBox(width: 16),
                        const SizedBox(width: 8),
                        Text(r.name),
                      ],
                    ),
                  ),
              ],
            ),
          IconButton(
            tooltip: 'Refresh orders',
            icon: const Icon(Icons.refresh),
            onPressed: () => ref.invalidate(commerceReadProvider(path)),
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
            data: (raw) {
              final allOrders = (raw['items'] as List)
                  .cast<Map>()
                  .map((m) => Json.from(m))
                  .toList();
              final totalCount = raw['total'] as int? ?? allOrders.length;
              final serverPendingCount =
                  raw['pendingCount'] as int? ??
                  allOrders
                      .where((o) => o['status'] == 'PENDING_RESTAURANT')
                      .length;

              final newOrders = allOrders
                  .where((o) => o['status'] == 'PENDING_RESTAURANT')
                  .toList();
              final kitchenOrders = allOrders
                  .where(
                    (o) =>
                        o['status'] == 'ACCEPTED' ||
                        o['status'] == 'PREPARING' ||
                        o['status'] == 'READY_FOR_PICKUP',
                  )
                  .toList();
              final historyOrders = allOrders
                  .where(
                    (o) =>
                        o['status'] == 'DELIVERED' || o['status'] == 'REJECTED',
                  )
                  .toList();

              final scheduledOrders = allOrders
                  .where(
                    (o) =>
                        o['deliveryMode'] == 'SCHEDULED' &&
                        ![
                          'DELIVERED',
                          'CANCELED',
                          'REJECTED',
                        ].contains(o['status']),
                  )
                  .toList();
              List<Json> filteredOrders;
              switch (_activeTab) {
                case 'scheduled':
                  filteredOrders = scheduledOrders;
                  break;
                case 'new':
                  filteredOrders = newOrders;
                  break;
                case 'kitchen':
                  filteredOrders = kitchenOrders;
                  break;
                case 'history':
                  filteredOrders = historyOrders;
                  break;
                case 'all':
                default:
                  filteredOrders = allOrders;
                  break;
              }

              return RefreshIndicator(
                onRefresh: () async {
                  ref.invalidate(commerceReadProvider(path));
                },
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                  children: [
                    LiveOrderBar(path: path),
                    const SizedBox(height: 8),

                    // Metrics Banner
                    _KitchenMetricsBanner(
                      restaurantName: activeRestaurant.name,
                      pendingCount: serverPendingCount,
                      inKitchenCount: kitchenOrders.length,
                      historyCount: historyOrders.length,
                      activeTab: _activeTab,
                      onTabSelected: (tab) => setState(() => _activeTab = tab),
                    ),
                    const SizedBox(height: 12),

                    // Filter Chips Row
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterPill(
                            label:
                                'Scheduled Orders (${scheduledOrders.length})',
                            selected: _activeTab == 'scheduled',
                            onTap: () => setState(() {
                              _activeTab = 'scheduled';
                              _page = 1;
                            }),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'All ($totalCount)',
                            selected: _activeTab == 'all',
                            onTap: () => setState(() => _activeTab = 'all'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'New ($serverPendingCount)',
                            selected: _activeTab == 'new',
                            badgeColor: serverPendingCount > 0
                                ? Colors.amber[800]
                                : null,
                            onTap: () => setState(() => _activeTab = 'new'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'In Kitchen (${kitchenOrders.length})',
                            selected: _activeTab == 'kitchen',
                            onTap: () => setState(() => _activeTab = 'kitchen'),
                          ),
                          const SizedBox(width: 8),
                          _FilterPill(
                            label: 'History (${historyOrders.length})',
                            selected: _activeTab == 'history',
                            onTap: () => setState(() => _activeTab = 'history'),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),

                    if (filteredOrders.isEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 48),
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.receipt_long_outlined,
                                size: 48,
                                color: scheme.outline,
                              ),
                              const SizedBox(height: 12),
                              Text(
                                _activeTab == 'new'
                                    ? 'No pending orders'
                                    : _activeTab == 'kitchen'
                                    ? 'No active orders in kitchen'
                                    : _activeTab == 'history'
                                    ? 'No historical orders yet'
                                    : 'No orders recorded for this kitchen',
                                style: theme.textTheme.titleMedium,
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'Incoming customer orders will appear here in real-time.',
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      )
                    else
                      for (final order in filteredOrders) ...[
                        OperationCard(
                          key: ValueKey(order['id']),
                          order: order,
                          scope: 'restaurant',
                          onChanged: () {
                            ref.invalidate(commerceReadProvider(path));
                          },
                        ),
                        const SizedBox(height: 10),
                      ],

                    if (totalCount > 20 || _page > 1) ...[
                      const SizedBox(height: 12),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          TextButton.icon(
                            icon: const Icon(Icons.arrow_back),
                            label: const Text('Previous'),
                            onPressed: _page > 1
                                ? () => setState(() => _page--)
                                : null,
                          ),
                          Text(
                            'Page $_page of ${(totalCount / 20).ceil().clamp(1, 9999)}',
                            style: theme.textTheme.bodySmall,
                          ),
                          TextButton.icon(
                            label: const Text('Next'),
                            icon: const Icon(Icons.arrow_forward),
                            onPressed: _page * 20 < totalCount
                                ? () => setState(() => _page++)
                                : null,
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            },
          ),
    );
  }
}

class _KitchenMetricsBanner extends StatelessWidget {
  final String restaurantName;
  final int pendingCount;
  final int inKitchenCount;
  final int historyCount;
  final String activeTab;
  final ValueChanged<String> onTabSelected;

  const _KitchenMetricsBanner({
    required this.restaurantName,
    required this.pendingCount,
    required this.inKitchenCount,
    required this.historyCount,
    required this.activeTab,
    required this.onTabSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>();

    return Container(
      padding: const EdgeInsets.all(14),
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
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: culinary?.pistachio ?? Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Accepting Orders · Hyderabad',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _MetricTile(
                  count: pendingCount,
                  label: 'Pending',
                  highlight: pendingCount > 0,
                  highlightColor: Colors.amber[800]!,
                  isSelected: activeTab == 'new',
                  onTap: () => onTabSelected('new'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  count: inKitchenCount,
                  label: 'Cooking',
                  highlight: inKitchenCount > 0,
                  highlightColor: scheme.primary,
                  isSelected: activeTab == 'kitchen',
                  onTap: () => onTabSelected('kitchen'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _MetricTile(
                  count: historyCount,
                  label: 'Completed',
                  highlight: false,
                  highlightColor: scheme.outline,
                  isSelected: activeTab == 'history',
                  onTap: () => onTabSelected('history'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MetricTile extends StatelessWidget {
  final int count;
  final String label;
  final bool highlight;
  final Color highlightColor;
  final bool isSelected;
  final VoidCallback onTap;

  const _MetricTile({
    required this.count,
    required this.label,
    required this.highlight,
    required this.highlightColor,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        child: Column(
          children: [
            Text(
              '$count',
              style: theme.textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
                color: highlight ? highlightColor : scheme.onSurface,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: theme.textTheme.labelSmall?.copyWith(
                color: scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterPill extends StatelessWidget {
  final String label;
  final bool selected;
  final Color? badgeColor;
  final VoidCallback onTap;

  const _FilterPill({
    required this.label,
    required this.selected,
    this.badgeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;

    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.bold : FontWeight.normal,
        color: selected
            ? scheme.onPrimaryContainer
            : badgeColor ?? scheme.onSurface,
      ),
    );
  }
}
