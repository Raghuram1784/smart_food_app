import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../pricing/pricing_repository.dart';

({String badge, String reason}) buildCustomerExplanation(
  SmartMeal meal, {
  required int index,
  required int pageTotal,
  required int? minLoadedTotal,
  required int loadedCount,
  required int? budget,
  required bool? vegetarian,
  required int? maxMinutes,
  required String sort,
}) {
  final quote = meal.quote;
  debugPrint(
    '[SmartMatch] item=${quote.dish.id} total=${quote.total} score=${meal.score} raw=${meal.explanations.join(" ")}',
  );

  final isFullResultSet = pageTotal == loadedCount;
  final isCheapestAll =
      isFullResultSet &&
      loadedCount > 1 &&
      minLoadedTotal != null &&
      quote.total == minLoadedTotal;

  String badge;
  if (budget != null && quote.total < budget) {
    badge = '₹${formatPaise(budget - quote.total)} below your budget';
  } else if (budget != null && quote.total == budget) {
    badge = 'Fits your ₹${formatPaise(budget)} budget';
  } else if (sort == 'value' && index == 0 && pageTotal > 1) {
    badge = 'Best value for your preferences';
  } else if (isCheapestAll) {
    badge = 'Lowest total among matching meals';
  } else {
    badge = 'Fees included in total';
  }

  String reason;
  if (budget != null &&
      (vegetarian == true || quote.dish.isVegetarian == true) &&
      quote.total <= budget) {
    reason = 'Vegetarian and within budget';
  } else if (isCheapestAll && !badge.startsWith('Lowest total')) {
    reason = 'Lowest total among matching meals';
  } else if (maxMinutes != null && quote.minutes <= maxMinutes) {
    reason = '${quote.minutes} min estimated delivery';
  } else if (index == 0 &&
      sort == 'value' &&
      pageTotal > 1 &&
      !badge.startsWith('Best value')) {
    reason = 'Best value for your preferences';
  } else {
    reason = '${quote.minutes} min estimated delivery · sample kitchen data';
  }

  return (badge: badge, reason: reason);
}

class SmartMealCard extends StatelessWidget {
  final SmartMeal meal;
  final String badge;
  final String reason;
  final bool comparing;
  final ValueChanged<bool> onCompareToggle;

  const SmartMealCard({
    super.key,
    required this.meal,
    required this.badge,
    required this.reason,
    required this.comparing,
    required this.onCompareToggle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>()!;
    final quote = meal.quote;
    final dish = quote.dish;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Material(
        color: scheme.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => showDish(context, dish),
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
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  quote.restaurant.name.toUpperCase(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: theme.textTheme.labelSmall?.copyWith(
                                    color: scheme.primary,
                                    letterSpacing: 0.7,
                                  ),
                                ),
                              ),
                              if (dish.isVegetarian == true) ...[
                                const SizedBox(width: 6),
                                Icon(
                                  Icons.eco_outlined,
                                  size: 14,
                                  color: scheme.secondary,
                                  semanticLabel: 'Vegetarian',
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            dish.name,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleMedium,
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 8,
                            runSpacing: 2,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Text(
                                '₹${formatPaise(quote.total)}',
                                style: theme.textTheme.titleLarge?.copyWith(
                                  fontFamily: AppType.ui,
                                  fontSize: 19,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                'final · ${quote.minutes} min · ★ ${quote.restaurant.rating}',
                                style: theme.textTheme.bodySmall,
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 9,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: culinary.pistachio,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              badge,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: scheme.onSecondaryContainer,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: FoodPhoto(dish.photoKey, height: 94, width: 94),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  reason,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    FilledButton.tonal(
                      key: ValueKey('quote-${dish.id}'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                      ),
                      onPressed: () => showDish(context, dish),
                      child: const Text('View meal & quote'),
                    ),
                    FilterChip(
                      key: ValueKey('compare-${dish.id}'),
                      visualDensity: VisualDensity.compact,
                      label: Text(comparing ? 'Comparing' : 'Compare'),
                      selected: comparing,
                      onSelected: onCompareToggle,
                    ),
                    TextButton(
                      style: TextButton.styleFrom(
                        minimumSize: const Size(0, 40),
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      onPressed: () =>
                          context.push('/restaurant/${quote.restaurant.id}'),
                      child: const Text('Menu'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
