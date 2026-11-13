import '../core/motion.dart';
import '../features/pricing/quote_panel.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design.dart';
import '../features/catalog/catalog.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/catalog_repository.dart';
import '../features/catalog/catalog_state.dart';

class FoodPhoto extends StatelessWidget {
  final String name, folder;
  final double? height, width;
  const FoodPhoto(
    this.name, {
    super.key,
    this.folder = 'food',
    this.height,
    this.width,
  });
  @override
  Widget build(BuildContext context) {
    final pixelRatio = MediaQuery.devicePixelRatioOf(context);
    final logicalWidth = width?.isFinite == true
        ? width!
        : MediaQuery.sizeOf(context).width;
    final decodeWidth = (logicalWidth * pixelRatio).ceil().clamp(160, 1600);
    return Image.asset(
      'assets/images/$folder/$name.jpg',
      height: height,
      width: width,
      fit: BoxFit.cover,
      cacheWidth: decodeWidth,
      filterQuality: FilterQuality.medium,
      semanticLabel: '$name photograph',
      frameBuilder: (context, child, frame, sync) => frame != null || sync
          ? child
          : SizedBox(
              height: height,
              width: width,
              child: ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainer,
                child: const Center(child: Icon(Icons.restaurant_outlined)),
              ),
            ),
      errorBuilder: (context, error, stack) => Semantics(
        label: 'Food photo unavailable',
        child: SizedBox(
          height: height,
          width: width,
          child: ColoredBox(
            color: Theme.of(context).colorScheme.surfaceContainer,
            child: const Center(
              child: Icon(Icons.image_not_supported_outlined),
            ),
          ),
        ),
      ),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String title;
  final VoidCallback? onTap;
  const SectionTitle(this.title, {super.key, this.onTap});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(top: 28, bottom: 14),
    child: Row(
      children: [
        Expanded(
          child: Text(title, style: Theme.of(context).textTheme.titleLarge),
        ),
        if (onTap != null)
          TextButton(onPressed: onTap, child: const Text('View all')),
      ],
    ),
  );
}

class RestaurantCard extends StatelessWidget {
  final Restaurant restaurant;
  const RestaurantCard(this.restaurant, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final from = restaurant.startingPricePaise;
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Material(
        color: theme.colorScheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Space.radius),
          side: BorderSide(color: theme.colorScheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => context.push('/restaurant/${restaurant.id}'),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              FoodPhoto(
                restaurant.image,
                folder: 'restaurants',
                height: 190,
                width: double.infinity,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            restaurant.name,
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: theme.extension<CulinaryColors>()!.pistachio,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.star_rounded, size: 15),
                              Text(
                                ' ${restaurant.rating}',
                                style: theme.textTheme.labelLarge,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      restaurant.localityName != null
                          ? '${restaurant.cuisine} · ${restaurant.localityName}'
                          : restaurant.cuisine,
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
                        Text(
                          '◷ ${restaurant.time}',
                          style: theme.textTheme.labelMedium,
                        ),
                        Text(
                          from == null
                              ? 'Menu coming soon'
                              : 'From ₹${formatPaise(from)} · sample',
                          style: theme.textTheme.labelMedium?.copyWith(
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
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

class DishTile extends StatelessWidget {
  final Dish dish;
  const DishTile(this.dish, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () => showDish(context, dish),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(dish.name, style: theme.textTheme.titleMedium),
                      const SizedBox(height: 5),
                      Text(
                        dish.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall,
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '₹${dish.displayPrice} · sample',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 100,
                  child: Column(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: FoodPhoto(
                          dish.photoKey,
                          height: 100,
                          width: 100,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        dish.availabilityStatus == 'AVAILABLE'
                            ? 'View dish'
                            : dish.availabilityStatus
                                  .replaceAll('_', ' ')
                                  .toLowerCase(),
                        style: theme.textTheme.labelSmall?.copyWith(
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showDish(BuildContext context, Dish dish) {
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    sheetAnimationStyle: AnimationStyle(
      duration: motionDuration(context, 320),
      reverseDuration: motionDuration(context, 220),
    ),
    isScrollControlled: true,
    useSafeArea: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .92,
    ),
    builder: (context) => Consumer(
      builder: (context, ref, _) => ref
          .watch(dishProvider(dish.id))
          .when(
            loading: () => const Padding(
              padding: EdgeInsets.all(48),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => CatalogFailure(
              error,
              () => ref.invalidate(dishProvider(dish.id)),
            ),
            data: (liveDish) => _dishContents(context, liveDish),
          ),
    ),
  );
}

Widget _dishContents(BuildContext context, Dish dish) {
  final theme = Theme.of(context);
  final scheme = theme.colorScheme;
  final available = dish.availabilityStatus == 'AVAILABLE';
  return SafeArea(
    top: false,
    child: SingleChildScrollView(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        24 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(18),
            child: FoodPhoto(
              dish.photoKey,
              height: 148,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Text(
                  dish.restaurantName.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelSmall?.copyWith(
                    letterSpacing: 1.1,
                    color: scheme.primary,
                  ),
                ),
              ),
              if (dish.isVegetarian == true)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: theme.extension<CulinaryColors>()!.pistachio,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('Veg', style: theme.textTheme.labelSmall),
                ),
            ],
          ),
          const SizedBox(height: 4),
          Text(dish.name, style: theme.textTheme.titleLarge),
          const SizedBox(height: 6),
          Text(
            dish.description,
            style: theme.textTheme.bodyMedium?.copyWith(
              color: scheme.onSurfaceVariant,
            ),
          ),
          if (!available) ...[
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: scheme.surfaceContainer,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: scheme.outlineVariant),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Currently ${dish.availabilityStatus.replaceAll('_', ' ').toLowerCase()} — live quotes and ordering are disabled for this dish.',
                    style: theme.textTheme.titleSmall,
                  ),
                  if (dish.availabilityReason != null &&
                      dish.availabilityReason!.trim().isNotEmpty) ...[
                    const SizedBox(height: 6),
                    Text(
                      dish.availabilityReason!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ],
              ),
            ),
          ],
          Consumer(
            builder: (context, ref, _) {
              final offline = ref.watch(catalogRepositoryProvider).offline;
              if (offline || !available) {
                return Padding(
                  padding: const EdgeInsets.only(top: 14),
                  child: Text(
                    '₹${dish.displayPrice} · sample menu price before fees',
                    style: theme.textTheme.titleMedium,
                  ),
                );
              }
              return DishQuotePanel(dish);
            },
          ),
          if (dish.variants.isNotEmpty && dish.variantOptions.isEmpty) ...[
            const SizedBox(height: 14),
            Text('Available sizes', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final variant in dish.variants) Chip(label: Text(variant)),
              ],
            ),
          ],
          if (dish.addOns.isNotEmpty && dish.addOnOptions.isEmpty) ...[
            const SizedBox(height: 14),
            Text('Add-ons', style: theme.textTheme.labelLarge),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final addOn in dish.addOns) Chip(label: Text(addOn)),
              ],
            ),
          ],
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Back to exploring'),
            ),
          ),
        ],
      ),
    ),
  );
}
