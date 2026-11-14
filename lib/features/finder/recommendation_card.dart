import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../shared/components.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/diet_preference.dart';
import '../commerce/commerce_repository.dart';
import '../commerce/commerce_widgets.dart';
import 'finder_models.dart';
import 'finder_theme.dart';

/// A recommended dish with its authoritative fee breakdown and budget status.
class RecommendationCard extends ConsumerWidget {
  final FinderRecommendation rec;
  final String? area;
  final int index;
  const RecommendationCard({super.key, required this.rec, required this.area, required this.index});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    return Container(
      key: ValueKey('finder-card-${rec.menuItemId}'),
      decoration: BoxDecoration(
        color: c.card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: rec.overBudget ? c.warn.withValues(alpha: .35) : c.outline),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: .05), blurRadius: 14, offset: const Offset(0, 4))],
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  ClipRRect(borderRadius: BorderRadius.circular(14), child: FoodPhoto(rec.photoKey, width: 92, height: 92)),
                  Positioned(
                    left: 6,
                    top: 6,
                    child: DecoratedBox(
                      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4)),
                      child: Padding(padding: const EdgeInsets.all(2), child: VegMark(veg: rec.isVegetarian, size: 14)),
                    ),
                  ),
                ],
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _StatusPill(rec: rec),
                    const SizedBox(height: 6),
                    Text(rec.name, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.titleMedium?.copyWith(color: c.charcoal, fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Row(children: [
                      Icon(Icons.storefront_outlined, size: 14, color: c.muted),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          [rec.restaurantName, if (rec.locality != null) rec.locality!.split(',').first].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.bodySmall?.copyWith(color: c.muted),
                        ),
                      ),
                    ]),
                    const SizedBox(height: 8),
                    Wrap(spacing: 6, runSpacing: 6, children: [
                      if (rec.nutrition case final n?) ...[
                        _Chip(icon: Icons.local_fire_department_outlined, label: '${n.caloriesKcal} kcal', color: c.coral, bg: c.warnBg),
                        _Chip(icon: Icons.fitness_center_outlined, label: '${_g(n.proteinG)} g protein', color: c.success, bg: c.successBg),
                      ] else
                        _Chip(icon: Icons.info_outline, label: 'Nutrition unavailable', color: c.muted, bg: c.paleGreen),
                      if (rec.spiceLevel > 0) _Chip(icon: Icons.whatshot_outlined, label: const ['', 'Mild', 'Medium', 'Hot'][rec.spiceLevel], color: c.warn, bg: c.warnBg),
                    ]),
                  ],
                ),
              ),
            ],
          ),
          if (rec.nutrition case final n?)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text('Estimate per ${n.servingDescription}${n.servingGrams != null ? ' (~${n.servingGrams} g)' : ''}', style: text.bodySmall?.copyWith(color: c.muted)),
            ),
          const SizedBox(height: 10),
          _PriceBreakdown(rec: rec),
          if (rec.reasons.isNotEmpty) ...[
            const SizedBox(height: 8),
            Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Icon(Icons.auto_awesome, size: 14, color: c.gold),
              const SizedBox(width: 6),
              Expanded(child: Text(rec.reasons.join(' · '), style: text.bodySmall?.copyWith(color: c.muted))),
            ]),
          ],
          if (rec.hasVariantChoices || rec.hasAddOns)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                rec.variantName != null ? 'Priced for ${rec.variantName}. Other sizes and add-ons are in View details.' : 'Add-ons available in View details.',
                style: text.bodySmall?.copyWith(color: c.muted),
              ),
            ),
          const SizedBox(height: 8),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            crossAxisAlignment: WrapCrossAlignment.center,
            runSpacing: 4,
            children: [
              TextButton.icon(
                key: ValueKey('finder-details-$index'),
                style: TextButton.styleFrom(foregroundColor: c.forest),
                onPressed: () => _details(context, ref),
                icon: const Icon(Icons.restaurant_menu, size: 18),
                label: const Text('View details'),
              ),
              Theme(
                data: Theme.of(context).copyWith(
                  colorScheme: Theme.of(context).colorScheme.copyWith(primary: c.forest, onPrimary: c.onForest),
                  textButtonTheme: TextButtonThemeData(style: TextButton.styleFrom(foregroundColor: c.forest)),
                ),
                child: AddToCartButton(
                  key: ValueKey('finder-add-$index'),
                  compact: true,
                  itemName: rec.name,
                  selection: rec.selection(area),
                  beforeAdd: () => _confirm(context, ref),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static String _g(num v) => v == v.roundToDouble() ? '${v.round()}' : v.toStringAsFixed(1);

  Future<void> _details(BuildContext context, WidgetRef ref) async {
    try {
      final dish = await ref.read(catalogRepositoryProvider).item(rec.menuItemId, CancelToken());
      if (context.mounted) showDish(context, dish);
    } catch (e) {
      if (context.mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(commerceError(e))));
    }
  }

  /// Asks before adding anything above budget, and re-quotes so a changed price is never added silently.
  Future<bool> _confirm(BuildContext context, WidgetRef ref) async {
    if (rec.overBudget) {
      final ok = await _ask(
        context,
        title: 'Above your budget',
        body: '${rec.name} comes to ${rupees(rec.totalPaise)}, which is ${rupees(rec.budgetDifferencePaise ?? 0)} above your ${rupees(rec.budgetPaise ?? 0)} budget. Add it anyway?',
        confirm: 'Add anyway',
      );
      if (!ok) return false;
    }
    if (area == null || !context.mounted) return true; // the cart quote re-prices at checkout
    final quote = await ref.read(commerceRepositoryProvider).request('POST', 'pricing/quote', {
      'restaurantId': rec.restaurantId,
      'menuItemId': rec.menuItemId,
      'area': area,
      'quantity': rec.quantity,
      'addOnIds': <String>[],
      'variantId': ?rec.variantId,
    });
    final now = (quote is Map ? quote['finalPayablePaise'] : null) as int?;
    if (now == null || now == rec.totalPaise || !context.mounted) return true;
    final over = rec.budgetPaise != null && now > rec.budgetPaise!;
    return _ask(
      context,
      title: 'Price updated',
      body: 'The total for ${rec.name} changed from ${rupees(rec.totalPaise)} to ${rupees(now)}${over ? ', which is above your ${rupees(rec.budgetPaise!)} budget' : ''}. Add it at the new price?',
      confirm: 'Add at ${rupees(now)}',
    );
  }

  static Future<bool> _ask(BuildContext context, {required String title, required String body, required String confirm}) async =>
      await showDialog<bool>(
        context: context,
        useRootNavigator: true,
        builder: (context) => AlertDialog(
          title: Text(title),
          content: Text(body),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            FilledButton(key: const ValueKey('finder-confirm-add'), onPressed: () => Navigator.pop(context, true), child: Text(confirm)),
          ],
        ),
      ) ??
      false;
}

class _StatusPill extends StatelessWidget {
  final FinderRecommendation rec;
  const _StatusPill({required this.rec});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final (label, icon, fg, bg) = switch ((rec.matchType, rec.budgetStatus)) {
      (_, 'ABOVE_BUDGET') => ('${rupees(rec.budgetDifferencePaise ?? 0)} above budget', Icons.north_east, c.warn, c.warnBg),
      ('SIMILAR', 'NO_BUDGET') => ('Similar taste', Icons.auto_awesome, c.charcoal, c.goldBg),
      ('SIMILAR', _) => ('Similar taste · within budget', Icons.auto_awesome, c.charcoal, c.goldBg),
      (_, 'EXACT_BUDGET') => ('Exact budget match', Icons.verified, c.success, c.successBg),
      (_, 'WITHIN_BUDGET') => ('Within budget', Icons.check_circle, c.success, c.successBg),
      _ => ('Matches your request', Icons.check_circle, c.success, c.successBg),
    };
    return DecoratedBox(
      key: ValueKey('finder-pill-${rec.budgetStatus}'),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelSmall?.copyWith(color: fg, fontWeight: FontWeight.w700))),
        ]),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color, bg;
  const _Chip({required this.icon, required this.label, required this.color, required this.bg});
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
            Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelMedium?.copyWith(color: color))),
          ]),
        ),
      );
}

class _PriceBreakdown extends StatelessWidget {
  final FinderRecommendation rec;
  const _PriceBreakdown({required this.rec});
  @override
  Widget build(BuildContext context) {
    final c = FinderColors.of(context);
    final text = Theme.of(context).textTheme;
    Widget row(String label, String value, {TextStyle? style, Key? key}) => Padding(
          padding: const EdgeInsets.symmetric(vertical: 1.5),
          child: Row(key: key, children: [
            Expanded(child: Text(label, style: style ?? text.bodyMedium?.copyWith(color: c.muted))),
            Text(value, style: style ?? text.bodyMedium?.copyWith(color: c.charcoal)),
          ]),
        );
    final over = rec.overBudget;
    final totalColor = over ? c.warn : rec.budgetStatus == 'NO_BUDGET' ? c.charcoal : c.success;
    return DecoratedBox(
      decoration: BoxDecoration(color: c.paleGreen.withValues(alpha: .6), borderRadius: BorderRadius.circular(14)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        child: Column(children: [
          row(rec.quantity > 1 ? 'Food (${rec.quantity} items)' : 'Food price', rupees(rec.foodPaise)),
          if (rec.discountPaise > 0) row('Discount', '−${rupees(rec.discountPaise)}'),
          if (rec.packagingPaise > 0) row('Packaging', rupees(rec.packagingPaise)),
          row('Delivery fee', rupees(rec.deliveryPaise)),
          if (rec.platformPaise > 0) row('Platform fee', rupees(rec.platformPaise)),
          if (rec.taxPaise > 0) row('Taxes', rupees(rec.taxPaise)),
          Divider(height: 12, color: c.outline),
          row('Total payable', rupees(rec.totalPaise),
              key: const ValueKey('finder-total'), style: text.titleMedium?.copyWith(color: totalColor, fontWeight: FontWeight.w800)),
          if (rec.budgetPaise != null)
            Align(
              alignment: Alignment.centerRight,
              child: Text(
                switch (rec.budgetStatus) {
                  'EXACT_BUDGET' => 'Exactly your ${rupees(rec.budgetPaise!)} budget',
                  'WITHIN_BUDGET' => '${rupees(-(rec.budgetDifferencePaise ?? 0))} under your ${rupees(rec.budgetPaise!)} budget',
                  _ => '${rupees(rec.budgetDifferencePaise ?? 0)} above your ${rupees(rec.budgetPaise!)} budget',
                },
                style: text.bodySmall?.copyWith(color: totalColor, fontWeight: FontWeight.w600),
              ),
            ),
        ]),
      ),
    );
  }
}
