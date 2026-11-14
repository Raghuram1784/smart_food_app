import '../core/motion.dart';
import '../features/pricing/quote_panel.dart';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../core/design.dart';
import '../features/catalog/catalog.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/catalog/catalog_repository.dart';
import '../features/catalog/catalog_state.dart';
import '../features/location/delivery_location_sheet.dart';
import '../features/catalog/diet_preference.dart';

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
                    const SizedBox(height: 8),
                    // Server-evaluated eligibility for the confirmed destination.
                    // No delivery ETA is shown: road routing is not available.
                    ServiceabilityBadge(restaurant.id),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 12,
                      runSpacing: 6,
                      children: [
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
                      Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        if (dish.isVegetarian != null) Padding(padding: const EdgeInsets.only(top: 3, right: 6), child: VegMark(veg: dish.isVegetarian!)),
                        Expanded(child: Text(dish.name, style: theme.textTheme.titleMedium)),
                      ]),
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
                      const SizedBox(height: 6),
                      NutritionLine(dish.nutrition),
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
              if (dish.isVegetarian != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    VegMark(veg: dish.isVegetarian!),
                    const SizedBox(width: 4),
                    Text(dish.isVegetarian! ? 'Veg' : 'Non-veg', style: theme.textTheme.labelSmall),
                  ],
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
          const SizedBox(height: 12),
          NutritionPanel(dish.nutrition),
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


/// Nutrition section for a dish. Shows "Nutrition unavailable" when the backend
/// has no record (never 0), labels estimates, and states the serving size.
class NutritionPanel extends StatelessWidget {
  final Nutrition? nutrition;
  const NutritionPanel(this.nutrition, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final n = nutrition;
    return Container(
      key: const ValueKey('nutrition-panel'),
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(14),
      ),
      child: n == null
          ? Row(children: [
              Icon(Icons.info_outline, size: 18, color: scheme.outline),
              const SizedBox(width: 8),
              Text('Nutrition unavailable', style: theme.textTheme.bodySmall),
            ])
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  Text('Nutrition', style: theme.textTheme.titleSmall),
                  const SizedBox(width: 8),
                  if (n.isEstimate)
                    DecoratedBox(
                      decoration: BoxDecoration(color: scheme.tertiaryContainer, borderRadius: BorderRadius.circular(8)),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        child: Text('Estimate', style: theme.textTheme.labelSmall),
                      ),
                    ),
                ]),
                const SizedBox(height: 2),
                Text(
                  'Per ${n.servingDescription}${n.servingGrams != null ? ' (~${n.servingGrams} g)' : ''} · base serving, excludes variants and add-ons',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 16,
                  runSpacing: 6,
                  children: [
                    _Macro('Calories', '${n.caloriesKcal} kcal'),
                    _Macro('Protein', '${_g(n.proteinG)} g'),
                    if (n.carbsG != null) _Macro('Carbs', '${_g(n.carbsG!)} g'),
                    if (n.fatG != null) _Macro('Fat', '${_g(n.fatG!)} g'),
                  ],
                ),
                if (n.isEstimate) ...[
                  const SizedBox(height: 6),
                  Text('Approximate values, not lab-tested or certified. ${n.source}', style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
                ],
              ],
            ),
    );
  }

  static String _g(double v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(1);
}

class _Macro extends StatelessWidget {
  final String label, value;
  const _Macro(this.label, this.value);
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(value, style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
        Text(label, style: theme.textTheme.labelSmall),
      ],
    );
  }
}

/// Compact "520 kcal | 28 g protein" chips for dish cards and lists, with a small
/// info action for provenance. Missing data says so; it is never shown as 0.
class NutritionLine extends StatelessWidget {
  final Nutrition? nutrition;
  final bool dense;
  const NutritionLine(this.nutrition, {super.key, this.dense = false});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final n = nutrition;
    final style = theme.textTheme.labelSmall?.copyWith(fontWeight: FontWeight.w700);
    Widget chip(IconData icon, String text, Color fg, Color bg) => DecoratedBox(
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: dense ? 6 : 8, vertical: 2),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(icon, size: dense ? 11 : 13, color: fg),
              const SizedBox(width: 3),
              Flexible(child: Text(text, maxLines: 1, overflow: TextOverflow.ellipsis, style: style?.copyWith(color: fg))),
            ]),
          ),
        );
    if (n == null) {
      return Text('Calories & protein unavailable',
          key: const ValueKey('nutrition-unavailable'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant));
    }
    final coral = dark ? const Color(0xFFF38A6C) : const Color(0xFFC2512F);
    final green = dark ? const Color(0xFF8FD3AE) : const Color(0xFF1E6B47);
    return Wrap(
      key: const ValueKey('nutrition-line'),
      spacing: 4,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        chip(Icons.local_fire_department_outlined, '${n.caloriesKcal} kcal', coral, coral.withValues(alpha: .12)),
        chip(Icons.fitness_center_outlined, '${NutritionPanel._g(n.proteinG)} g protein', green, green.withValues(alpha: .12)),
        if (!dense)
          InkResponse(
            radius: 16,
            onTap: () => showDialog<void>(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('About these values'),
                content: Text('${n.isEstimate ? 'Estimated' : 'Measured'} per ${n.servingDescription}${n.servingGrams != null ? ' (~${n.servingGrams} g)' : ''}. ${n.source}'),
                actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
              ),
            ),
            child: Padding(padding: const EdgeInsets.all(2), child: Icon(Icons.info_outline, size: 14, color: theme.colorScheme.onSurfaceVariant)),
          ),
      ],
    );
  }
}
