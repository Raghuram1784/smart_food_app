import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/design.dart';
import '../../core/motion.dart';
import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../pricing/pricing_repository.dart';
import '../pricing/quote_panel.dart';

void showMealComparison(
  BuildContext context,
  String area,
  List<String> ids, {
  String? bestValueDishId,
}) {
  final request = (area: area, ids: ids.join(','));
  showModalBottomSheet<void>(
    context: context,
    useRootNavigator: true,
    useSafeArea: true,
    isScrollControlled: true,
    constraints: BoxConstraints(
      maxHeight: MediaQuery.sizeOf(context).height * .9,
    ),
    sheetAnimationStyle: AnimationStyle(duration: motionDuration(context, 320)),
    builder: (context) => Consumer(
      builder: (context, ref, _) {
        final theme = Theme.of(context);
        final scheme = theme.colorScheme;
        return SafeArea(
          top: false,
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Compare meals', style: theme.textTheme.titleLarge),
                const SizedBox(height: 4),
                Text(
                  'Side-by-side single-meal quotes under the same pricing policy.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 16),
                ref
                    .watch(compareProvider(request))
                    .when(
                      loading: () => const Padding(
                        padding: EdgeInsets.all(32),
                        child: Center(child: CircularProgressIndicator()),
                      ),
                      error: (e, _) => QuoteFailure(
                        e,
                        () => ref.invalidate(compareProvider(request)),
                      ),
                      data: (quotes) => _ComparisonMatrix(
                        quotes: quotes,
                        bestValueDishId: bestValueDishId,
                      ),
                    ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: scheme.outlineVariant),
                    ),
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Back to meals'),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    ),
  );
}

class _ComparisonMatrix extends StatelessWidget {
  final List<MealQuote> quotes;
  final String? bestValueDishId;
  const _ComparisonMatrix({required this.quotes, this.bestValueDishId});

  int _fees(MealQuote q) =>
      q.amounts['deliveryPaise']! +
      q.amounts['packagingPaise']! +
      q.amounts['platformPaise']!;

  @override
  Widget build(BuildContext context) {
    if (quotes.isEmpty) return const SizedBox.shrink();
    final minTotal = quotes.map((q) => q.total).reduce(math.min);
    final maxTotal = quotes.map((q) => q.total).reduce(math.max);
    final minMinutes = quotes.map((q) => q.minutes).reduce(math.min);
    final maxMinutes = quotes.map((q) => q.minutes).reduce(math.max);
    final maxRating = quotes.map((q) => q.restaurant.rating).reduce(math.max);
    final uniqueLowest = quotes.where((q) => q.total == minTotal).length == 1;
    final uniqueFastest =
        quotes.where((q) => q.minutes == minMinutes).length == 1;
    final feesVary = quotes.map(_fees).toSet().length > 1;

    return LayoutBuilder(
      builder: (context, constraints) {
        final useColumns = constraints.maxWidth >= 520 || quotes.length <= 2;
        if (useColumns) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < quotes.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                Expanded(
                  child: _ComparisonColumn(
                    quote: quotes[i],
                    isBestValue:
                        bestValueDishId != null &&
                        quotes[i].dish.id == bestValueDishId,
                    isLowestTotal: uniqueLowest && quotes[i].total == minTotal,
                    isFastest: uniqueFastest && quotes[i].minutes == minMinutes,
                    minTotal: minTotal,
                    maxTotal: maxTotal,
                    minMinutes: minMinutes,
                    maxMinutes: maxMinutes,
                    maxRating: maxRating,
                    fees: _fees(quotes[i]),
                    feesVary: feesVary,
                  ),
                ),
              ],
            ],
          );
        }
        final cardWidth = (constraints.maxWidth * 0.47).clamp(152.0, 210.0);
        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < quotes.length; i++) ...[
                if (i > 0) const SizedBox(width: 10),
                SizedBox(
                  width: cardWidth,
                  child: _ComparisonColumn(
                    quote: quotes[i],
                    isBestValue:
                        bestValueDishId != null &&
                        quotes[i].dish.id == bestValueDishId,
                    isLowestTotal: uniqueLowest && quotes[i].total == minTotal,
                    isFastest: uniqueFastest && quotes[i].minutes == minMinutes,
                    minTotal: minTotal,
                    maxTotal: maxTotal,
                    minMinutes: minMinutes,
                    maxMinutes: maxMinutes,
                    maxRating: maxRating,
                    fees: _fees(quotes[i]),
                    feesVary: feesVary,
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _ComparisonColumn extends StatelessWidget {
  final MealQuote quote;
  final bool isBestValue;
  final bool isLowestTotal;
  final bool isFastest;
  final int minTotal, maxTotal, minMinutes, maxMinutes, fees;
  final double maxRating;
  final bool feesVary;

  const _ComparisonColumn({
    required this.quote,
    required this.isBestValue,
    required this.isLowestTotal,
    required this.isFastest,
    required this.minTotal,
    required this.maxTotal,
    required this.minMinutes,
    required this.maxMinutes,
    required this.maxRating,
    required this.fees,
    required this.feesVary,
  });

  String _distinction() {
    if (isLowestTotal && maxTotal > minTotal) {
      return 'Lowest total · saves ₹${formatPaise(maxTotal - quote.total)}';
    }
    if (isFastest && maxMinutes > minMinutes) {
      return '${maxMinutes - quote.minutes} min faster estimate';
    }
    if (quote.restaurant.rating == maxRating) {
      return 'Top sample rating (${quote.restaurant.rating})';
    }
    return '+₹${formatPaise(quote.total - minTotal)} vs lowest';
  }

  Widget _metricRow(BuildContext context, String label, String value) =>
      Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.labelSmall),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final culinary = theme.extension<CulinaryColors>()!;
    final badgeText = isBestValue
        ? 'Best value'
        : isLowestTotal
        ? 'Lowest total'
        : isFastest
        ? 'Fastest'
        : null;
    final subtotal = quote.amounts['basePaise']!;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: (isBestValue || isLowestTotal)
              ? scheme.primary
              : scheme.outlineVariant,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: FoodPhoto(
              quote.dish.photoKey,
              height: 90,
              width: double.infinity,
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            height: 24,
            child: badgeText == null
                ? const SizedBox.shrink()
                : Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: culinary.pistachio,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      badgeText,
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: scheme.onSecondaryContainer,
                      ),
                    ),
                  ),
          ),
          const SizedBox(height: 6),
          Text(
            quote.restaurant.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.labelSmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 2),
          SizedBox(
            height: 40,
            child: Text(
              quote.dish.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleSmall,
            ),
          ),
          const Divider(height: 16),
          Text('Final payable', style: theme.textTheme.labelSmall),
          Text(
            '₹${formatPaise(quote.total)}',
            style: theme.textTheme.titleLarge?.copyWith(
              fontFamily: AppType.ui,
              fontSize: 20,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          _metricRow(context, 'Delivery', '${quote.minutes} min estimate'),
          _metricRow(context, 'Sample rating', '★ ${quote.restaurant.rating}'),
          _metricRow(
            context,
            'Availability',
            quote.dish.availabilityStatus == 'AVAILABLE'
                ? 'Available (${quote.areaName})'
                : quote.dish.availabilityStatus.toLowerCase(),
          ),
          _metricRow(
            context,
            feesVary ? 'Item + fees (varies)' : 'Item + fees',
            '₹${formatPaise(subtotal)} + ₹${formatPaise(fees)}',
          ),
          const SizedBox(height: 4),
          Text(
            _distinction(),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall?.copyWith(color: scheme.primary),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: FilledButton.tonal(
              style: FilledButton.styleFrom(
                minimumSize: const Size(0, 40),
                padding: const EdgeInsets.symmetric(horizontal: 10),
              ),
              onPressed: () {
                Navigator.pop(context);
                showDish(context, quote.dish);
              },
              child: const Text('Inspect'),
            ),
          ),
        ],
      ),
    );
  }
}
