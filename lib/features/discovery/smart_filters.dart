import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../catalog/catalog.dart';
import '../catalog/catalog_repository.dart';
import '../pricing/pricing_repository.dart';

typedef FilterSelection = ({
  String area,
  String? category,
  String? cuisine,
  String? restaurant,
  int? budget,
  bool? vegetarian,
  int? minutes,
  double? rating,
});
int? parseBudget(String text) {
  if (text.trim().isEmpty) return null;
  if (!RegExp(r'^\d{1,7}(\.\d{1,2})?$').hasMatch(text.trim())) {
    throw const FormatException(
      'Enter a positive amount with up to two decimal places.',
    );
  }
  final parts = text.trim().split('.');
  final value =
      int.parse(parts[0]) * 100 +
      (parts.length == 2 ? int.parse(parts[1].padRight(2, '0')) : 0);
  if (value > 100000000) {
    throw const FormatException('The maximum supported amount is ₹10,00,000.');
  }
  return value;
}

class SmartFilterSheet extends ConsumerStatefulWidget {
  final FilterSelection initial;
  const SmartFilterSheet(this.initial, {super.key});
  @override
  ConsumerState<SmartFilterSheet> createState() => _SmartFilterSheetState();
}

class _SmartFilterSheetState extends ConsumerState<SmartFilterSheet> {
  late String area = widget.initial.area;
  late String? category = widget.initial.category,
      cuisine = widget.initial.cuisine,
      restaurant = widget.initial.restaurant;
  late bool? vegetarian = widget.initial.vegetarian;
  late int? minutes = widget.initial.minutes;
  late double? rating = widget.initial.rating;
  late final budget = TextEditingController(
    text: widget.initial.budget == null
        ? ''
        : _budgetText(widget.initial.budget!),
  );
  String? error;
  String _budgetText(int paise) => formatPaise(paise);
  @override
  void dispose() {
    budget.dispose();
    super.dispose();
  }

  Widget select(
    String label,
    String? value,
    List<({String id, String name})> choices,
    void Function(String?) change, {
    bool all = true,
  }) => Padding(
    padding: const EdgeInsets.only(bottom: 12),
    child: DropdownButtonFormField<String>(
      key: ValueKey('$label-$value-${choices.length}'),
      initialValue: choices.any((c) => c.id == value) ? value : null,
      isExpanded: true,
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 14,
          vertical: 12,
        ),
      ),
      items: [
        if (all) const DropdownMenuItem(value: null, child: Text('Any')),
        for (final c in choices)
          DropdownMenuItem(
            value: c.id,
            child: Text(c.name, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: change,
    ),
  );

  void _clearFilters() {
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      category = null;
      cuisine = null;
      restaurant = null;
      vegetarian = null;
      minutes = null;
      rating = null;
      budget.clear();
      error = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final areas = ref.watch(areasProvider),
        categories = ref.watch(categoriesProvider),
        cuisines = ref.watch(cuisineChoicesProvider),
        kitchens = ref.watch(kitchenChoicesProvider(area));
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          4,
          20,
          20 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Refine your search',
                      style: theme.textTheme.titleLarge,
                    ),
                  ),
                  TextButton(
                    onPressed: _clearFilters,
                    child: const Text('Clear filters'),
                  ),
                ],
              ),
              Text(
                'Budgets filter by final payable including delivery & fees.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              Text(
                'Prices are for your selected delivery address. Change it from Home → Deliver to.',
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Any budget'),
                    selected: budget.text.trim().isEmpty,
                    onSelected: (_) => setState(() {
                      budget.clear();
                      error = null;
                    }),
                  ),
                  for (final preset in [150, 250, 400])
                    ChoiceChip(
                      label: Text('Up to ₹$preset'),
                      selected: budget.text.trim() == '$preset',
                      onSelected: (_) => setState(() {
                        budget.text = '$preset';
                        error = null;
                      }),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              TextField(
                key: const ValueKey('budget-input'),
                controller: budget,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                onChanged: (_) => setState(() => error = null),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  labelText: 'Maximum final payable',
                  prefixText: '₹ ',
                  hintText: 'No limit',
                  errorText: error,
                ),
              ),
              const SizedBox(height: 14),
              select('Food category', category, [
                for (final c in categories.asData?.value ?? <FoodCategory>[])
                  (id: c.id, name: c.name),
              ], (v) => setState(() => category = v)),
              select(
                'Cuisine',
                cuisine,
                cuisines.asData?.value ?? [],
                (v) => setState(() => cuisine = v),
              ),
              select(
                'Restaurant',
                restaurant,
                kitchens.asData?.value ?? [],
                (v) => setState(() => restaurant = v),
              ),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: const Text('Vegetarian only'),
                subtitle: const Text('Matches stored vegetarian attribute'),
                value: vegetarian == true,
                onChanged: (v) => setState(() => vegetarian = v ? true : null),
              ),
              const SizedBox(height: 8),
              Text('Delivery time estimate', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Any estimate'),
                    selected: minutes == null,
                    onSelected: (_) => setState(() => minutes = null),
                  ),
                  for (final n in [20, 30, 45, 60])
                    ChoiceChip(
                      label: Text('Within $n minutes'),
                      selected: minutes == n,
                      onSelected: (_) => setState(() => minutes = n),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text('Minimum sample rating', style: theme.textTheme.labelLarge),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    label: const Text('Any rating'),
                    selected: rating == null,
                    onSelected: (_) => setState(() => rating = null),
                  ),
                  for (final n in [4.0, 4.5, 4.8])
                    ChoiceChip(
                      label: Text('$n+'),
                      selected: rating == n,
                      onSelected: (_) => setState(() => rating = n),
                    ),
                ],
              ),
              if (areas.hasError ||
                  categories.hasError ||
                  cuisines.hasError ||
                  kitchens.hasError)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: TextButton(
                    onPressed: () {
                      ref.invalidate(areasProvider);
                      ref.invalidate(categoriesProvider);
                      ref.invalidate(cuisineChoicesProvider);
                      ref.invalidate(kitchenChoicesProvider(area));
                    },
                    child: const Text('Some choices could not load. Retry'),
                  ),
                ),
              const SizedBox(height: 18),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    try {
                      final amount = parseBudget(budget.text);
                      Navigator.pop(context, (
                        area: area,
                        category: category,
                        cuisine: cuisine,
                        restaurant: restaurant,
                        budget: amount,
                        vegetarian: vegetarian,
                        minutes: minutes,
                        rating: rating,
                      ));
                    } on FormatException catch (e) {
                      setState(() => error = e.message);
                    }
                  },
                  child: const Text('Show matching meals'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
