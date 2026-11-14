import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog_repository.dart';
import '../catalog/catalog_state.dart';
import '../catalog/diet_preference.dart';
import '../location/delivery_location_sheet.dart';
import '../../shared/components.dart';
import '../commerce/commerce_widgets.dart';
import '../commerce/commerce_repository.dart' show customerIdProvider;
import '../group/group_screens.dart' show startGroupOrder;

class RestaurantScreen extends ConsumerWidget {
  final String id;
  const RestaurantScreen({super.key, required this.id});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(restaurantMenuProvider(id))
        .when(
          loading: () => Scaffold(
            appBar: AppBar(),
            body: const Center(child: CircularProgressIndicator()),
          ),
          error: (error, _) => Scaffold(
            appBar: AppBar(title: const Text('Kitchen unavailable')),
            body: Center(
              child: CatalogFailure(
                error,
                () => ref.invalidate(restaurantMenuProvider(id)),
              ),
            ),
          ),
          data: (data) => _content(context, ref, data),
        );
  }

  Widget _content(BuildContext context, WidgetRef ref, RestaurantMenu data) {
    final restaurant = data.restaurant;
    // Veg / Non-Veg / Both applies to the actual menu items (server isVegetarian).
    final diet = ref.watch(dietPreferenceProvider);
    final allItems = data.items;
    final menu = allItems.where(diet.allows).toList();
    return Scaffold(
      // Stay on the menu after adding; the cart is one tap away.
      bottomNavigationBar: const ViewCartBar(),
      body: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(restaurantMenuProvider(id));
          try {
            await ref.read(restaurantMenuProvider(id).future);
          } catch (_) {
            /* Provider renders the error. */
          }
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverAppBar(
              actions: const [CartShortcut()],
              expandedHeight: 240,
              pinned: true,
              leading: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton.filledTonal(
                  tooltip: 'Back',
                  onPressed: () {
                    if (context.canPop()) {
                      context.pop();
                    } else {
                      context.go('/');
                    }
                  },
                  icon: const Icon(Icons.arrow_back),
                ),
              ),
              flexibleSpace: FlexibleSpaceBar(
                background: FoodPhoto(
                  restaurant.image,
                  folder: 'restaurants',
                  height: 240,
                  width: double.infinity,
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.all(24),
              sliver: SliverList.list(
                children: [
                  const CatalogStatus(),
                  Text(
                    restaurant.cuisine.toUpperCase(),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      letterSpacing: 2,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    restaurant.name,
                    style: Theme.of(context).textTheme.titleMedium
                        ?.copyWith(fontSize: 28, height: 1.2),
                  ),
                  const SizedBox(height: 16),
                  Text(restaurant.description),
                  if (restaurant.localityName != null ||
                      restaurant.serviceAreaNames.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    Text(
                      [
                        if (restaurant.localityName != null)
                          restaurant.localityName!,
                        if (restaurant.serviceAreaNames.isNotEmpty)
                          'Service areas: ${restaurant.serviceAreaNames.join(', ')}',
                      ].join(' · '),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                  const SizedBox(height: 14),
                  ServiceabilityBadge(restaurant.id, showReason: true),
                  const SizedBox(height: 10),
                  if (ref.watch(customerIdProvider) != null)
                    OutlinedButton.icon(
                      key: const ValueKey('start-group-order'),
                      onPressed: () => startGroupOrder(context, ref, restaurantId: restaurant.id, restaurantName: restaurant.name),
                      icon: const Icon(Icons.groups_2_outlined),
                      label: const Text('Start a group order'),
                    ),
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 12,
                    runSpacing: 8,
                    children: [
                      Chip(
                        avatar: const Icon(Icons.star_outline, size: 18),
                        label: Text('${restaurant.rating} sample rating'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    'Demo kitchen · illustrative prices. No delivery time is estimated without route data. Review the server-calculated bill before checkout.',
                    style: TextStyle(fontSize: 12),
                  ),
                  Text(
                    '${restaurant.operatingStatus.toLowerCase()} · ${restaurant.deliveryAvailable ? 'Delivery eligible' : 'Delivery eligibility not confirmed'}',
                  ),
                  const SizedBox(height: 14),
                  const DietSelector(),
                  if (menu.isEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Text(allItems.isEmpty
                          ? 'No menu items yet.'
                          : 'No ${diet.label} dishes on this menu. Switch to Both to see everything.'),
                    ),
                  for (final section in menu.map((d) => d.section).toSet()) ...[
                    SectionTitle(section),
                    ...menu
                        .where((d) => d.section == section)
                        .map(DishTile.new),
                  ],
                  const SizedBox(height: 32),
                  const Text(
                    'Demo orders are saved for restaurant review. No real payment is collected.',
                  ),
                  const SizedBox(height: 32),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
