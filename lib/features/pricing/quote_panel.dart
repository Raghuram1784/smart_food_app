import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import '../../core/motion.dart';
import '../catalog/catalog.dart';
import 'pricing_repository.dart';
import '../commerce/commerce_widgets.dart';

class QuoteFailure extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const QuoteFailure(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) {
    String message = 'We couldn’t check this meal right now. Please retry.';
    if (error is DioException) {
      final response = (error as DioException).response;
      final code = response?.statusCode;
      if ((code == 400 || code == 404 || code == 422) &&
          response?.data is Map) {
        final detail = response?.data['error']?['message'];
        if (detail is String && detail.trim().isNotEmpty) message = detail;
      }
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Column(
        children: [
          const Icon(Icons.info_outline),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          TextButton(onPressed: retry, child: const Text('Check again')),
        ],
      ),
    );
  }
}

class PriceBreakdown extends StatelessWidget {
  final MealQuote quote;
  final VoidCallback? onRefresh;
  const PriceBreakdown(this.quote, {super.key, this.onRefresh});

  Widget _priceRow(
    BuildContext context,
    String label,
    String value, {
    Color? valueColor,
  }) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(label, style: Theme.of(context).textTheme.bodyMedium),
        ),
        const SizedBox(width: 12),
        Text(
          value,
          style: Theme.of(context).textTheme.titleSmall
              ?.copyWith(color: valueColor),
        ),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final basePaise = quote.amounts['basePaise']!;
    final variantPaise = quote.amounts['variantPaise']!;
    final addOnPaise = quote.amounts['addOnPaise']!;
    final customizationPaise = variantPaise + addOnPaise;
    final deliveryPaise = quote.amounts['deliveryPaise']!;
    final packagingPaise = quote.amounts['packagingPaise']!;
    final platformPaise = quote.amounts['platformPaise']!;
    final discountPaise = quote.amounts['discountPaise']!;
    final taxPaise = quote.amounts['taxPaise']!;
    final validUntil = TimeOfDay.fromDateTime(quote.expiresAt.toLocal())
        .format(context);
    final selectedSummary = [
      if (quote.variantName != null) quote.variantName!,
      if (quote.addOnNames.isNotEmpty) quote.addOnNames.join(', '),
    ].join(' · ');

    debugPrint(
      '[PricingQuote] item=${quote.dish.id} area=${quote.areaName} total=${quote.total} rules=${quote.ruleCodes.join(',')}',
    );

    return Material(
      color: scheme.surfaceContainer,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(18),
        side: BorderSide(color: scheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectedSummary.isNotEmpty) ...[
              Text(
                selectedSummary,
                style: theme.textTheme.labelMedium?.copyWith(
                  color: scheme.primary,
                ),
              ),
              const SizedBox(height: 8),
            ],
            _priceRow(
              context,
              'Item subtotal (${quote.quantity} × ₹${formatPaise(basePaise ~/ quote.quantity)})',
              '₹${formatPaise(basePaise)}',
            ),
            if (customizationPaise > 0)
              _priceRow(
                context,
                'Customization charges',
                '+₹${formatPaise(customizationPaise)}',
              ),
            _priceRow(
              context,
              'Delivery fee',
              '₹${formatPaise(deliveryPaise)}',
            ),
            _priceRow(
              context,
              'Packaging fee',
              '₹${formatPaise(packagingPaise)}',
            ),
            _priceRow(
              context,
              'Platform fee',
              '₹${formatPaise(platformPaise)}',
            ),
            if (discountPaise > 0)
              _priceRow(
                context,
                'Discount',
                '−₹${formatPaise(discountPaise)}',
                valueColor: scheme.secondary,
              ),
            if (taxPaise > 0)
              _priceRow(context, 'Tax', '₹${formatPaise(taxPaise)}'),
            const Divider(height: 22),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Final payable', style: theme.textTheme.titleMedium),
                      Text(
                        'Preview total · No order placed',
                        style: theme.textTheme.bodySmall,
                      ),
                    ],
                  ),
                ),
                Text(
                  '₹${formatPaise(quote.total)}',
                  style: theme.textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '${quote.areaName} · ${quote.minutes} min est. · Valid until $validUntil',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                if (onRefresh != null)
                  TextButton.icon(
                    style: TextButton.styleFrom(
                      visualDensity: VisualDensity.compact,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    onPressed: onRefresh,
                    icon: const Icon(Icons.refresh, size: 16),
                    label: const Text('Refresh quote'),
                  ),
              ],
            ),
            Theme(
              data: theme.copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                childrenPadding: const EdgeInsets.only(bottom: 4),
                dense: true,
                title: Text(
                  'Quote & fee details',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(quote.taxNotice, style: theme.textTheme.bodySmall),
                        const SizedBox(height: 4),
                        Text(
                          '${quote.notice} Prices and availability are rechecked when refreshed.',
                          style: theme.textTheme.bodySmall,
                        ),
                        if (quote.ruleCodes.isNotEmpty) ...[
                          const SizedBox(height: 4),
                          Text(
                            'Policy ${quote.ruleVersion} · Applied rules: ${quote.ruleCodes.join(', ')}',
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DishQuotePanel extends ConsumerStatefulWidget {
  final Dish dish;
  const DishQuotePanel(this.dish, {super.key});
  @override
  ConsumerState<DishQuotePanel> createState() => _DishQuotePanelState();
}

class _DishQuotePanelState extends ConsumerState<DishQuotePanel> {
  String? variant;
  final addOns = <String>{};
  int quantity = 1;
  final promotion = TextEditingController();
  String? appliedPromotion;
  @override
  void dispose() {
    promotion.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.dish;
    final theme = Theme.of(context);
    final area = ref.watch(locationProvider);
    final request = (
      item: d.id,
      restaurant: d.restaurantId,
      area: area.id,
      variant: variant,
      addOns: (addOns.toList()..sort()).join(','),
      quantity: quantity,
      promotion: appliedPromotion,
    );
    final state = ref.watch(quoteProvider(request));
    final current = state.asData?.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text('Customize meal', style: theme.textTheme.titleMedium),
            ),
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => setState(() {
                variant = null;
                addOns.clear();
                quantity = 1;
                promotion.clear();
                appliedPromotion = null;
              }),
              child: const Text('Reset selections'),
            ),
          ],
        ),
        if (d.variantOptions.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('Available sizes', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in d.variantOptions)
                ChoiceChip(
                  label: Text(
                    '${option.name} · +₹${formatPaise(option.pricePaise)}${option.available ? '' : ' · unavailable'}',
                  ),
                  selected: (variant ?? current?.variantId) == option.id,
                  onSelected: option.available
                      ? (_) => setState(() => variant = option.id)
                      : null,
                ),
            ],
          ),
        ],
        if (d.addOnOptions.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Add-ons', style: theme.textTheme.labelMedium),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: [
              for (final option in d.addOnOptions)
                FilterChip(
                  label: Text(
                    '${option.name} · +₹${formatPaise(option.pricePaise)}${option.available ? '' : ' · unavailable'}',
                  ),
                  selected: addOns.contains(option.id),
                  onSelected: option.available
                      ? (selected) => setState(() {
                          if (selected) {
                            addOns.add(option.id);
                          } else {
                            addOns.remove(option.id);
                          }
                        })
                      : null,
                ),
            ],
          ),
        ],
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Row(
                children: [
                  Text('Quantity', style: theme.textTheme.labelLarge),
                  const SizedBox(width: 4),
                  IconButton(
                    tooltip: 'Decrease quantity',
                    onPressed: quantity > 1
                        ? () => setState(() => quantity--)
                        : null,
                    icon: const Icon(Icons.remove_circle_outline),
                  ),
                  Text('$quantity', style: theme.textTheme.titleSmall),
                  IconButton(
                    tooltip: 'Increase quantity',
                    onPressed: quantity < 20
                        ? () => setState(() => quantity++)
                        : null,
                    icon: const Icon(Icons.add_circle_outline),
                  ),
                ],
              ),
            ),
          ],
        ),
        TextField(
          controller: promotion,
          decoration: InputDecoration(
            isDense: true,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 10,
            ),
            labelText: 'Promotion code (optional)',
            suffixIcon: IconButton(
              tooltip: 'Apply promotion',
              onPressed: () => setState(
                () => appliedPromotion = promotion.text.trim().isEmpty
                    ? null
                    : promotion.text.trim().toUpperCase(),
              ),
              icon: const Icon(Icons.arrow_forward),
            ),
          ),
        ),
        const SizedBox(height: 14),
        AddToCartButton(
          enabled: current != null && !state.isLoading,
          selection: {
            'restaurantId': d.restaurantId,
            'menuItemId': d.id,
            'area': area.id,
            'quantity': quantity,
            if (variant ?? current?.variantId case final String selected)
              'variantId': selected,
            'addOnIds': addOns.toList(),
          },
        ),
        AnimatedSize(
          duration: motionDuration(context),
          alignment: Alignment.topCenter,
          child: state.when(
            skipLoadingOnRefresh: false,
            loading: () => const Padding(
              padding: EdgeInsets.all(20),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) =>
                QuoteFailure(e, () => ref.invalidate(quoteProvider(request))),
            data: (quote) => Reveal(
              key: ValueKey(quote.fingerprint),
              child: PriceBreakdown(
                quote,
                onRefresh: () => ref.invalidate(quoteProvider(request)),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
