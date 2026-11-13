import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../../core/design.dart';
import '../../shared/components.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_state.dart';
import 'home_widgets.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref
        .watch(homeCatalogProvider)
        .when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (error, _) => Center(
            child: CatalogFailure(
              error,
              () => ref.invalidate(homeCatalogProvider),
            ),
          ),
          data: (catalog) => RefreshIndicator(
            onRefresh: () async {
              ref.invalidate(homeCatalogProvider);
              try {
                await ref.read(homeCatalogProvider.future);
              } catch (_) {
                /* Provider renders the error. */
              }
            },
            child: _content(context, ref, catalog),
          ),
        );
  }

  Widget _content(BuildContext context, WidgetRef ref, HomeCatalog catalog) {
    final restaurants = catalog.restaurants;
    final dishes = catalog.dishes;
    final featured = restaurants.where((r) => r.id == 'hearth').firstOrNull;
    final localKitchen =
        restaurants.where((r) => r.id == 'tiffin').firstOrNull ??
        restaurants.firstOrNull;
    final firstBite =
        dishes.where((d) => d.id == 'paneer').firstOrNull ?? dishes.firstOrNull;
    final area = ref.watch(locationProvider);
    final theme = Theme.of(context);
    final accents = theme.extension<CulinaryColors>()!;
    return SafeArea(
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        children: [
          const CatalogStatus(),
          Row(
            children: [
              Icon(
                Icons.location_on_outlined,
                color: theme.colorScheme.primary,
                size: 22,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: InkWell(
                  onTap: () => _location(context, ref),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'YOUR NEIGHBOURHOOD · HYDERABAD · DEMO',
                          style: theme.textTheme.labelSmall?.copyWith(
                            letterSpacing: 1,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                area.name,
                                style: theme.textTheme.labelLarge,
                              ),
                            ),
                            const Icon(Icons.expand_more, size: 18),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              IconButton.filledTonal(
                tooltip: 'Profile and appearance',
                onPressed: () => context.go('/profile'),
                icon: const Icon(Icons.person_outline),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            'A little hungry,\nRaghu?',
            style: theme.textTheme.headlineLarge,
          ),
          const SizedBox(height: 8),
          Text(
            'Good food. A better kind of everyday.',
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 20),
          Semantics(
            button: true,
            label: 'Search dishes and restaurants',
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () => context.go('/search'),
              child: InputDecorator(
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                ),
                child: Text(
                  'What are you craving?',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ),
          ),
          const SectionTitle('Follow your cravings'),
          HomeCategories(catalog.categories), const SizedBox(height: 24),
          if (localKitchen != null) EditorialFeature(localKitchen),
          SectionTitle(
            'Worth a first bite',
            onTap: () => context.go('/search'),
          ),
          if (firstBite != null) DishTile(firstBite),
          if (dishes.isEmpty)
            const Text(
              'The catalog is taking a breather. Pull down to refresh.',
            ),
          SectionTitle(
            'Little everyday joys',
            onTap: () => context.go('/search?affordable=true'),
          ),
          Material(
            color: accents.pistachio,
            borderRadius: BorderRadius.circular(20),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.go('/search?affordable=true'),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'BIG COMFORT. SMALL SPEND.',
                            style: theme.textTheme.labelSmall?.copyWith(
                              letterSpacing: 1,
                              color: theme.colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Your ₹250\nhappy place.',
                            style: theme.textTheme.headlineMedium,
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Explore sample-priced favourites →',
                            style: theme.textTheme.labelMedium,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(50),
                      child: const FoodPhoto('idli', height: 92, width: 92),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SectionTitle('Kitchens we love'),
          ...restaurants.map(RestaurantCard.new),
          // Preserve the original featured kitchen as a distinct collection.
          if (featured != null)
            Material(
              color: accents.seaGlass,
              borderRadius: BorderRadius.circular(20),
              child: InkWell(
                borderRadius: BorderRadius.circular(20),
                onTap: () => context.push('/restaurant/${featured.id}'),
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'THE SLOW FOOD EDIT',
                        style: theme.textTheme.labelSmall?.copyWith(
                          letterSpacing: 1.4,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Good things take fire.',
                        style: theme.textTheme.titleLarge,
                      ),
                      const SizedBox(height: 8),
                      Text('Explore ${featured.name} →'),
                    ],
                  ),
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text(
            'A LITTLE DISCOVERY. A LOT OF FLAVOUR.',
            style: theme.textTheme.labelSmall?.copyWith(letterSpacing: 1),
          ),
          const SizedBox(height: 8),
          Text(
            'Illustrative prices, ratings and delivery times. Ordering is not yet available.',
            style: theme.textTheme.bodySmall,
          ),
        ],
      ),
    );
  }

  void _location(BuildContext context, WidgetRef ref) =>
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (context) => SafeArea(
          child: Consumer(
            builder: (context, ref, _) {
              final current = ref.watch(locationProvider);
              final loaded = ref.watch(areasProvider).asData?.value;
              final areas = (loaded != null && loaded.isNotEmpty)
                  ? loaded
                  : ServiceArea.hyderabadAreas;
              return ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.sizeOf(context).height * 0.78,
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: ListView(
                          shrinkWrap: true,
                          children: [
                            Text(
                              'Your neighbourhood',
                              textAlign: TextAlign.center,
                              style: Theme.of(context).textTheme.headlineMedium,
                            ),
                            const Padding(
                              padding: EdgeInsets.all(12),
                              child: Text(
                                'Hyderabad · Demo locations only. No live delivery coverage.',
                                textAlign: TextAlign.center,
                              ),
                            ),
                            for (final area in areas)
                              ListTile(
                                title: Text(area.name),
                                subtitle: Text('${area.city}, Telangana'),
                                trailing: current.id == area.id
                                    ? const Icon(Icons.check)
                                    : null,
                                onTap: () {
                                  ref
                                      .read(locationProvider.notifier)
                                      .select(area);
                                  Navigator.pop(context);
                                },
                              ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      );
}
