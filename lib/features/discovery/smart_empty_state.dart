import 'package:flutter/material.dart';

import '../../core/motion.dart';
import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../pricing/pricing_repository.dart';

class SmartEmptyState extends StatelessWidget {
  final String areaName;
  final String queryText;
  final int? budget;
  final int? maxMinutes;
  final EmptyDiagnosis? diagnosis;
  final VoidCallback onResetFilters;
  final VoidCallback onResetAll;
  final VoidCallback onOpenLocality;
  final ValueChanged<int> onIncreaseBudget;
  final VoidCallback onViewAboveBudget;
  final VoidCallback onRemoveTimeLimit;

  const SmartEmptyState({
    super.key,
    required this.areaName,
    required this.queryText,
    required this.budget,
    required this.maxMinutes,
    required this.diagnosis,
    required this.onResetFilters,
    required this.onResetAll,
    required this.onOpenLocality,
    required this.onIncreaseBudget,
    required this.onViewAboveBudget,
    required this.onRemoveTimeLimit,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final diag = diagnosis;
    final reason = diag?.reason;

    if (reason == EmptyReason.seasonalOrUnavailable &&
        diag != null &&
        diag.unavailable.isNotEmpty) {
      final firstReason = diag.unavailable
          .map((d) => d.availabilityReason)
          .whereType<String>()
          .where((r) => r.trim().isNotEmpty)
          .firstOrNull;
      return Reveal(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: scheme.surfaceContainer,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: scheme.outlineVariant),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.event_busy_outlined, color: scheme.primary),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Seasonal or currently unavailable',
                            style: theme.textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      firstReason ??
                          'Matching dishes in $areaName are temporarily unavailable for live quotes.',
                      style: theme.textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    OutlinedButton(
                      onPressed: onResetAll,
                      child: const Text('Browse available meals'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              Text(
                'Unavailable in catalog (not orderable)',
                style: theme.textTheme.labelLarge,
              ),
              const SizedBox(height: 6),
              for (final dish in diag.unavailable) ...[
                DishTile(dish),
                if (dish.availabilityReason != null &&
                    dish.availabilityReason!.trim().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      dish.availabilityReason!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
              ],
            ],
          ),
        ),
      );
    }

    IconData icon = Icons.ramen_dining_outlined;
    String title = 'Nothing fits just yet.';
    String subtitle =
        'Try a wider budget or fewer filters. Only meals matching every selection are shown.';
    final actions = <Widget>[];

    switch (reason) {
      case EmptyReason.noKitchensInLocality:
        icon = Icons.location_off_outlined;
        title = 'No open kitchens serve $areaName right now.';
        subtitle = 'Try switching your delivery locality to discover active kitchens nearby.';
        actions.add(
          FilledButton.tonal(
            onPressed: onOpenLocality,
            child: const Text('Change locality'),
          ),
        );
        break;
      case EmptyReason.exceedsBudget:
        final cheapest = diag?.cheapestTotalPaise;
        final altCount = diag?.alternativeCount ?? 0;
        icon = Icons.account_balance_wallet_outlined;
        title = budget != null
            ? 'No matches within ₹${formatPaise(budget!)}.'
            : 'Nothing fits just yet.';
        subtitle = cheapest != null
            ? 'The lowest final payable matching your preferences in $areaName is ₹${formatPaise(cheapest)} (delivery & fees included).'
            : subtitle;
        if (cheapest != null) {
          actions.add(
            FilledButton.tonal(
              onPressed: () => onIncreaseBudget(cheapest),
              child: Text('Increase budget to ₹${formatPaise(cheapest)}'),
            ),
          );
        }
        if (budget != null && altCount > 0) {
          actions.add(
            OutlinedButton(
              onPressed: onViewAboveBudget,
              child: Text(
                'View $altCount alternatives above ₹${formatPaise(budget!)}',
              ),
            ),
          );
        }
        actions.add(
          TextButton(
            onPressed: onResetFilters,
            child: const Text('Reset search'),
          ),
        );
        break;
      case EmptyReason.exceedsTime:
        final fastest = diag?.fastestMinutes;
        icon = Icons.schedule_outlined;
        title = maxMinutes != null
            ? 'No kitchens estimate delivery within $maxMinutes min.'
            : 'Nothing fits your delivery window.';
        subtitle = fastest != null
            ? 'The fastest matching kitchen in $areaName estimates $fastest min.'
            : subtitle;
        actions.add(
          FilledButton.tonal(
            onPressed: onRemoveTimeLimit,
            child: const Text('Remove delivery-time filter'),
          ),
        );
        actions.add(
          TextButton(
            onPressed: onResetFilters,
            child: const Text('Reset search'),
          ),
        );
        break;
      case EmptyReason.noMatchingDishes:
        icon = Icons.search_off_outlined;
        title = queryText.trim().isNotEmpty
            ? 'No matching dishes for "${queryText.trim()}".'
            : 'No matching dishes in $areaName.';
        subtitle =
            'Check spelling or clear active filters to browse all open meals in $areaName.';
        actions.add(
          OutlinedButton(
            onPressed: onResetAll,
            child: const Text('Reset search'),
          ),
        );
        break;
      case EmptyReason.seasonalOrUnavailable:
      case null:
        actions.add(
          OutlinedButton(
            onPressed: onResetAll,
            child: const Text('Reset search'),
          ),
        );
    }

    return Reveal(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 28),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: scheme.surfaceContainer,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: scheme.outlineVariant),
          ),
          child: Column(
            children: [
              Icon(icon, size: 42, color: scheme.primary),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.textTheme.titleLarge,
              ),
              const SizedBox(height: 8),
              Text(
                subtitle,
                textAlign: TextAlign.center,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              Wrap(
                spacing: 10,
                runSpacing: 8,
                alignment: WrapAlignment.center,
                children: actions,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
