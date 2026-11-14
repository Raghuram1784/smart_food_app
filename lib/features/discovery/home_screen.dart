import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_state.dart';
import '../catalog/diet_preference.dart';
import '../location/delivery_destination.dart';
import '../location/delivery_location_sheet.dart';
import 'home_widgets.dart';
import 'promo_carousel.dart';
import '../finder/finder_screen.dart';
import '../finder/finder_theme.dart';

/// Customer Home. Opens immediately with no location or address prompt.
/// Every section is built from backend catalog data for the delivery area
/// (restaurants that deliver there and their dishes); the Veg/Non-Veg/Both
/// preference is applied by the server.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(homeCatalogProvider);
    return RefreshIndicator(
      onRefresh: () async {
        ref.invalidate(homeCatalogProvider);
        try {
          await ref.read(homeCatalogProvider.future);
        } catch (_) {}
      },
      child: CustomScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: _Header()),
          ...catalog.when(
            loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
            error: (e, _) => [
              SliverFillRemaining(hasScrollBody: false, child: Center(child: CatalogFailure(e, () => ref.invalidate(homeCatalogProvider)))),
            ],
            data: (c) => [SliverToBoxAdapter(child: _HomeBody(catalog: c))],
          ),
        ],
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FinderColors.of(context);
    final onBand = theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(onSurface: c.onForest, onSurfaceVariant: c.onForest.withValues(alpha: .78), primary: c.gold),
      textTheme: theme.textTheme.apply(bodyColor: c.onForest, displayColor: c.onForest),
      iconTheme: IconThemeData(color: c.onForest),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Material(
          color: c.forest,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(bottom: Radius.circular(28))),
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 12, 18),
              child: Theme(
                data: onBand,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Row(children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: c.onForest.withValues(alpha: .12), shape: BoxShape.circle),
                      child: Icon(Icons.location_on, color: c.gold, size: 20),
                    ),
                    const SizedBox(width: 8),
                    const Expanded(child: DeliveryLocationBar()),
                    IconButton(
                      tooltip: 'Profile and appearance',
                      onPressed: () => context.go('/account'),
                      icon: Icon(Icons.account_circle_outlined, color: c.onForest, size: 28),
                    ),
                  ]),
                  const SizedBox(height: 10),
                  const _SearchBar(),
                ]),
              ),
            ),
          ),
        ),
        const Padding(padding: EdgeInsets.fromLTRB(16, 14, 16, 4), child: SizedBox(width: double.infinity, child: DietSelector())),
        const Padding(padding: EdgeInsets.symmetric(horizontal: 16), child: CatalogStatus()),
      ],
    );
  }
}

class _SearchBar extends StatelessWidget {
  const _SearchBar();
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Material(
      color: c.ivory,
      borderRadius: BorderRadius.circular(28),
      clipBehavior: Clip.antiAlias,
      child: Row(children: [
        Expanded(
          child: Semantics(
            button: true,
            label: 'Search dishes and restaurants',
            child: InkWell(
              key: const ValueKey('home-search'),
              onTap: () => context.go('/search'),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                child: Row(children: [
                  Icon(Icons.search, color: c.muted),
                  const SizedBox(width: 10),
                  Expanded(child: Text('Search biryani, dosa, restaurants…', maxLines: 1, overflow: TextOverflow.ellipsis, style: text.bodyMedium?.copyWith(color: c.muted))),
                ]),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Tooltip(
            message: 'Find food with AI',
            child: InkWell(
              key: const ValueKey('home-search-ai'),
              borderRadius: BorderRadius.circular(20),
              onTap: () => context.push('/finder'),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(color: c.paleGreen, borderRadius: BorderRadius.circular(20)),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.auto_awesome, size: 16, color: c.forest),
                  const SizedBox(width: 4),
                  Text('AI', style: text.labelLarge?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
                ]),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _HomeBody extends ConsumerWidget {
  final HomeCatalog catalog;
  const _HomeBody({required this.catalog});

  List<PromoSlide> _slides(List<Restaurant> restaurants) {
    const featured = ['biryani', 'dosa', 'paneer', 'bowls', 'chaat', 'desserts', 'pizza', 'burgers'];
    final byId = {for (final c in catalog.categories) c.id: c};
    final slides = <PromoSlide>[
      for (final id in featured)
        if (byId[id] case final c?)
          PromoSlide(image: c.image, eyebrow: 'Craving', title: '${c.name} from kitchens near you', cta: 'Explore ${c.name}', route: '/search?category=${c.id}'),
    ].take(4).toList();
    if (restaurants.isNotEmpty) {
      final r = restaurants.first;
      slides.insert(slides.isEmpty ? 0 : 1, PromoSlide(image: r.image, folder: 'restaurants', eyebrow: 'Delivers to you', title: r.name, cta: 'Browse menu', route: '/restaurant/${r.id}'));
    }
    return slides;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final area = ref.watch(deliveryServiceAreaProvider);
    final eligibility = ref.watch(serviceabilityProvider).asData?.value;
    final restaurants = [...catalog.restaurants];
    // Outlets that deliver to the confirmed address first (the server already scopes Home to the area).
    // Then outlets located in the customer's own locality before neighbours that also deliver.
    int rank(Restaurant r) =>
        (eligibility?[r.id]?.eligible == true ? 2 : 0) + (area != null && (r.localityName ?? '').startsWith(area.name.split(',').first) ? 1 : 0);
    restaurants.sort((a, b) => rank(b) - rank(a));
    final dishes = catalog.dishes.where((d) => d.availabilityStatus == 'AVAILABLE').toList();
    bool isMain(Dish d) => !const {'beverages', 'desserts', 'bakery'}.contains(d.categoryId);
    List<Dish> onePerKitchen(Iterable<Dish> list, {Set<String> skip = const {}}) {
      final seen = <String>{};
      return [for (final d in list) if (!skip.contains(d.id) && seen.add(d.restaurantId)) d].take(10).toList();
    }

    const mains = ['biryani', 'meals', 'paneer', 'kebabs', 'indo-chinese', 'telangana-andhra', 'pizza', 'burgers', 'bowls', 'dosa'];
    final popular = onePerKitchen(dishes.where((d) => mains.contains(d.categoryId)));
    final recommended = onePerKitchen(dishes.where((d) => isMain(d) && d.nutrition != null && d.pricePaise <= 30000), skip: {for (final d in popular) d.id});
    final affordable = (dishes.where((d) => isMain(d) && d.pricePaise <= 15000).toList()..sort((a, b) => a.pricePaise.compareTo(b.pricePaise))).take(12).toList();
    final protein = (dishes.where((d) => (d.nutrition?.proteinG ?? 0) >= 20).toList()
          ..sort((a, b) => b.nutrition!.proteinG.compareTo(a.nutrition!.proteinG)))
        .take(12)
        .toList();
    final diet = ref.watch(dietPreferenceProvider);
    final t = MediaQuery.textScalerOf(context).scale(14) / 14;
    final areaName = area?.name.split(',').first;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 8),
        PromoCarousel(slides: _slides(restaurants), height: 172),
        _SectionHeader(
          title: 'Restaurants in your area',
          subtitle: areaName != null
              ? '${restaurants.length} outlets deliver to $areaName${diet == DietPreference.both ? '' : ' · ${diet.label}'}'
              : 'Add a delivery address to see who delivers to you',
          action: 'View all',
          onAction: () => context.push('/restaurants'),
        ),
        SizedBox(
          height: 128 + 96 * t,
          child: restaurants.isEmpty
              ? const _Empty('No kitchens match this filter.')
              : ListView.separated(
                  key: const ValueKey('home-restaurants'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: restaurants.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => RestaurantTile(restaurants[i]),
                ),
        ),
        const _SectionHeader(title: 'What\'s on your mind?'),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 16), child: HomeCategories(catalog.categories)),
        _DishRow(title: 'Popular meals', subtitle: 'Biryanis, thalis, curries and more near you', dishes: popular),
        _DishRow(title: 'Recommended for you', subtitle: 'Balanced picks with nutrition info', dishes: recommended),
        _DishRow(title: 'Under ₹150', subtitle: 'Menu price · delivery and fees shown at checkout', dishes: affordable, onMore: () => context.go('/search?affordable=true')),
        _DishRow(title: 'High-protein meals', subtitle: '20 g+ protein, estimated per serving', dishes: protein),
        const Padding(padding: EdgeInsets.fromLTRB(16, 20, 16, 0), child: FinderEntryCard()),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          child: Text(
            'Demo catalog: outlets and prices are illustrative. Delivery eligibility is checked by the server for your address at checkout.',
            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final String? subtitle;
  final String? action;
  final VoidCallback? onAction;
  const _SectionHeader({required this.title, this.subtitle, this.action, this.onAction});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FinderColors.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 22, 8, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700, color: c.charcoal)),
                if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
              ],
            ),
          ),
          if (action != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(foregroundColor: c.forest),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Text(action!), const Icon(Icons.chevron_right, size: 18)]),
            ),
        ],
      ),
    );
  }
}

class _DishRow extends StatelessWidget {
  final String title;
  final String? subtitle;
  final List<Dish> dishes;
  final VoidCallback? onMore;
  const _DishRow({required this.title, required this.dishes, this.subtitle, this.onMore});
  @override
  Widget build(BuildContext context) {
    if (dishes.isEmpty) return const SizedBox.shrink(); // no empty rows on Home
    final t = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, subtitle: subtitle, action: onMore == null ? null : 'See more', onAction: onMore),
        SizedBox(
          height: 132 + 128 * t,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: dishes.length,
            separatorBuilder: (_, _) => const SizedBox(width: 12),
            itemBuilder: (_, i) => DishCard(dishes[i]),
          ),
        ),
      ],
    );
  }
}

class _Empty extends StatelessWidget {
  final String text;
  const _Empty(this.text);
  @override
  Widget build(BuildContext context) => Center(child: Padding(padding: const EdgeInsets.all(20), child: Text(text, textAlign: TextAlign.center)));
}

/// Restaurant outlet card for horizontal browsing: brand, outlet locality, cuisine, delivery status.
class RestaurantTile extends StatelessWidget {
  final Restaurant restaurant;
  const RestaurantTile(this.restaurant, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FinderColors.of(context);
    final r = restaurant;
    return SizedBox(
      width: 236,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: BorderSide(color: c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/restaurant/${r.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodPhoto(r.image, folder: 'restaurants', height: 112, width: 236),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800, color: c.charcoal), maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.place_outlined, size: 13, color: c.muted),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          [if (r.localityName != null) r.localityName!.split(',').first, r.cuisine].join(' · '),
                          style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    ServiceabilityBadge(r.id),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact dish card: photo, veg mark, name, kitchen, price, calories/protein, add.
class DishCard extends StatelessWidget {
  final Dish dish;
  const DishCard(this.dish, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = FinderColors.of(context);
    final d = dish;
    return SizedBox(
      width: 168,
      child: Material(
        color: c.card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: c.outline)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDish(context, d),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(children: [
                FoodPhoto(d.photoKey, height: 112, width: 168),
                if (d.isVegetarian != null)
                  Positioned(
                    left: 8,
                    top: 8,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                      child: Padding(padding: const EdgeInsets.all(2), child: VegMark(veg: d.isVegetarian!)),
                    ),
                  ),
                Positioned(
                  right: 8,
                  bottom: 8,
                  child: Material(
                    color: c.forest,
                    shape: const CircleBorder(),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => showDish(context, d),
                      child: Padding(padding: const EdgeInsets.all(6), child: Icon(Icons.add, size: 18, color: c.onForest, semanticLabel: 'Add ${d.name}')),
                    ),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge?.copyWith(color: c.charcoal, fontWeight: FontWeight.w700)),
                    Text(d.restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall?.copyWith(color: c.muted)),
                    const SizedBox(height: 4),
                    Text('₹${d.displayPrice}', style: theme.textTheme.labelLarge?.copyWith(color: c.forest, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 4),
                    NutritionLine(d.nutrition, dense: true),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// "View all restaurants": every catalog restaurant from the backend.
class AllRestaurantsScreen extends ConsumerWidget {
  const AllRestaurantsScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(title: const Text('All restaurants')),
      body: ref.watch(homeCatalogProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: CatalogFailure(e, () => ref.invalidate(homeCatalogProvider))),
            data: (c) => ListView(
              padding: const EdgeInsets.all(16),
              children: [
                const DietSelector(),
                const SizedBox(height: 12),
                if (c.restaurants.isEmpty) const _Empty('No kitchens match this filter.'),
                for (final r in c.restaurants) RestaurantCard(r),
              ],
            ),
          ),
    );
  }
}
