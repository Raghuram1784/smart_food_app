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

/// Customer Home. Opens immediately with no location or address prompt.
/// Every section is built from backend catalog data (restaurants, dishes,
/// categories); the Veg/Non-Veg/Both preference is applied by the server.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final catalog = ref.watch(homeCatalogProvider);
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(homeCatalogProvider);
          try {
            await ref.read(homeCatalogProvider.future);
          } catch (_) {}
        },
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            const SliverPadding(
              padding: EdgeInsets.fromLTRB(20, 8, 20, 0),
              sliver: SliverToBoxAdapter(child: _Header()),
            ),
            ...catalog.when(
              loading: () => [const SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator()))],
              error: (e, _) => [
                SliverFillRemaining(hasScrollBody: false, child: Center(child: CatalogFailure(e, () => ref.invalidate(homeCatalogProvider)))),
              ],
              data: (c) => [SliverToBoxAdapter(child: _HomeBody(catalog: c))],
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header();
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const CatalogStatus(),
        Row(
          children: [
            Icon(Icons.location_on_outlined, color: theme.colorScheme.primary, size: 22),
            const SizedBox(width: 8),
            const Expanded(child: DeliveryLocationBar()),
            IconButton.filledTonal(
              tooltip: 'Profile and appearance',
              onPressed: () => context.go('/account'),
              icon: const Icon(Icons.person_outline),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Text('A little hungry?', style: theme.textTheme.headlineMedium),
        const SizedBox(height: 12),
        Semantics(
          button: true,
          label: 'Search dishes and restaurants',
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => context.go('/search'),
            child: InputDecorator(
              decoration: const InputDecoration(prefixIcon: Icon(Icons.search)),
              child: Text(
                'Search dishes or restaurants',
                style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        const SizedBox(width: double.infinity, child: DietSelector()),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _HomeBody extends ConsumerWidget {
  final HomeCatalog catalog;
  const _HomeBody({required this.catalog});

  List<PromoSlide> _slides(List<Restaurant> restaurants) {
    const featured = ['biryani', 'pizza', 'dosa', 'burger', 'dessert', 'chai', 'meals'];
    final byId = {for (final c in catalog.categories) c.id: c};
    final slides = <PromoSlide>[
      for (final id in featured)
        if (byId[id] case final c?)
          PromoSlide(image: c.image, eyebrow: 'Craving', title: '${c.name} picks from local kitchens', cta: 'Explore ${c.name}', route: '/search?category=${c.id}'),
    ].take(4).toList();
    final top = [...restaurants]..sort((a, b) => b.rating.compareTo(a.rating));
    if (top.isNotEmpty) {
      final r = top.first;
      slides.insert(slides.isEmpty ? 0 : 1, PromoSlide(image: r.image, folder: 'restaurants', eyebrow: 'Featured kitchen', title: r.name, cta: 'Browse menu', route: '/restaurant/${r.id}'));
    }
    return slides;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final eligibility = ref.watch(serviceabilityProvider).asData?.value;
    final restaurants = [...catalog.restaurants];
    // Restaurants that deliver to the confirmed address first; all remain browsable.
    if (eligibility != null) {
      restaurants.sort((a, b) => (eligibility[b.id]?.eligible == true ? 1 : 0) - (eligibility[a.id]?.eligible == true ? 1 : 0));
    }
    final dishes = catalog.dishes.where((d) => d.availabilityStatus == 'AVAILABLE').toList();
    final rating = {for (final r in catalog.restaurants) r.id: r.rating};

    // Recommended: one dish per kitchen for variety.
    final seen = <String>{};
    final recommended = [for (final d in dishes) if (seen.add(d.restaurantId)) d].take(10).toList();
    final popular = ([...dishes]..sort((a, b) => (rating[b.restaurantId] ?? 0).compareTo(rating[a.restaurantId] ?? 0))).take(10).toList();
    final affordable = (dishes.where((d) => d.pricePaise <= 25000).toList()..sort((a, b) => a.pricePaise.compareTo(b.pricePaise))).take(10).toList();
    final diet = ref.watch(dietPreferenceProvider);
    // Horizontal rows need a fixed height; grow it with the user's text size.
    final t = MediaQuery.textScalerOf(context).scale(14) / 14;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 12), child: FinderEntryCard()),
        PromoCarousel(slides: _slides(catalog.restaurants)),
        const Padding(padding: EdgeInsets.fromLTRB(20, 4, 20, 0), child: SectionTitle('What are you craving?')),
        Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: HomeCategories(catalog.categories)),
        _SectionHeader(
          title: 'Browse restaurants',
          subtitle: '${restaurants.length} kitchens${diet == DietPreference.both ? '' : ' with ${diet.label} options'}',
          action: 'View all',
          onAction: () => context.push('/restaurants'),
        ),
        SizedBox(
          height: 150 + 118 * t,
          child: restaurants.isEmpty
              ? const _Empty('No kitchens match this filter.')
              : ListView.separated(
                  key: const ValueKey('home-restaurants'),
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  itemCount: restaurants.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 12),
                  itemBuilder: (_, i) => RestaurantTile(restaurants[i]),
                ),
        ),
        _DishRow(title: 'Recommended for you', dishes: recommended),
        _DishRow(title: 'Popular right now', subtitle: 'From top-rated kitchens', dishes: popular),
        _DishRow(title: 'Affordable meals', subtitle: 'Under ₹250 (sample prices)', dishes: affordable, onMore: () => context.go('/search?affordable=true')),
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
          child: Text(
            'Demo catalog: kitchens, prices and ratings are illustrative. Delivery eligibility is checked by the server for your address at checkout.',
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 22, 12, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
                if (subtitle != null) Text(subtitle!, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ],
            ),
          ),
          if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
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
    final t = MediaQuery.textScalerOf(context).scale(14) / 14;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _SectionHeader(title: title, subtitle: subtitle, action: onMore == null ? null : 'See more', onAction: onMore),
        SizedBox(
          height: 140 + 116 * t,
          child: dishes.isEmpty
              ? const _Empty('No dishes match this filter yet.')
              : ListView.separated(
                  scrollDirection: Axis.horizontal,
                  padding: const EdgeInsets.symmetric(horizontal: 20),
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

/// Compact restaurant card for horizontal browsing.
class RestaurantTile extends StatelessWidget {
  final Restaurant restaurant;
  const RestaurantTile(this.restaurant, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final r = restaurant;
    return SizedBox(
      width: 250,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: theme.colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/restaurant/${r.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(children: [
                FoodPhoto(r.image, folder: 'restaurants', height: 130, width: 250),
                Positioned(
                  right: 8,
                  top: 8,
                  child: DecoratedBox(
                    decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.6), borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        const Icon(Icons.star_rounded, size: 14, color: Colors.amber),
                        Text(' ${r.rating}', style: theme.textTheme.labelSmall?.copyWith(color: Colors.white)),
                      ]),
                    ),
                  ),
                ),
              ]),
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.name, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700), maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      [r.cuisine, if (r.localityName != null) r.localityName!].join(' · '),
                      style: theme.textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    ServiceabilityBadge(r.id),
                  ],
                ),
              ),
              const Spacer(),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 0, 4, 2),
                child: TextButton.icon(
                  onPressed: () => context.push('/restaurant/${r.id}'),
                  icon: const Icon(Icons.restaurant_menu, size: 18),
                  label: const Text('Browse menu'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact dish card; opens the dish sheet (variants, add-ons, add to cart).
class DishCard extends StatelessWidget {
  final Dish dish;
  const DishCard(this.dish, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final d = dish;
    return SizedBox(
      width: 168,
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: theme.colorScheme.outlineVariant)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDish(context, d),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodPhoto(d.photoKey, height: 112, width: 168),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      if (d.isVegetarian != null) ...[VegMark(veg: d.isVegetarian!), const SizedBox(width: 6)],
                      Expanded(child: Text(d.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: theme.textTheme.labelLarge)),
                    ]),
                    const SizedBox(height: 2),
                    Text(d.restaurantName, maxLines: 1, overflow: TextOverflow.ellipsis, style: theme.textTheme.bodySmall),
                    const SizedBox(height: 4),
                    Text('₹${d.displayPrice}', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.primary, fontWeight: FontWeight.w700)),
                    if (d.nutrition != null)
                      Text(
                        '~${d.nutrition!.caloriesKcal} kcal · ${d.nutrition!.proteinG.round()} g protein',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
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
