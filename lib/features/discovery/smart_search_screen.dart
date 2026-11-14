import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/motion.dart';
import '../catalog/diet_preference.dart';
import '../location/delivery_destination.dart';
import '../location/delivery_location_sheet.dart';
import '../catalog/catalog.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_state.dart';
import '../pricing/pricing_repository.dart';
import '../pricing/quote_panel.dart';
import 'meal_comparison_sheet.dart';
import 'smart_empty_state.dart';
import 'smart_filters.dart';
import 'smart_meal_card.dart';

class SmartSearchScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  final bool affordable;
  const SmartSearchScreen({
    super.key,
    this.initialCategory,
    this.affordable = false,
  });
  @override
  ConsumerState<SmartSearchScreen> createState() => _SmartSearchScreenState();
}

class _SmartSearchScreenState extends ConsumerState<SmartSearchScreen> {
  final text = TextEditingController();
  Timer? debounce;
  String queryText = '', sort = 'value';
  late String? category = widget.initialCategory?.toLowerCase();
  String? cuisine, restaurant;
  late int? budget = widget.affordable ? 25000 : null;
  bool? vegetarian;
  int? minutes;
  double? rating;
  int page = 1;
  int? previousBudgetNotice;
  int _lastKnownTotal = 0;
  final Map<int, List<SmartMeal>> _pageCache = {};
  final selected = <String>{};

  @override
  void dispose() {
    debounce?.cancel();
    text.dispose();
    super.dispose();
  }

  void _resetPagination() {
    page = 1;
    _lastKnownTotal = 0;
    _pageCache.clear();
    selected.clear();
  }

  void resetAll() {
    debounce?.cancel();
    text.clear();
    setState(() {
      queryText = '';
      category = null;
      cuisine = null;
      restaurant = null;
      budget = null;
      vegetarian = null;
      minutes = null;
      rating = null;
      previousBudgetNotice = null;
      sort = 'value';
      _resetPagination();
    });
  }

  void resetFiltersOnly() {
    setState(() {
      category = null;
      cuisine = null;
      restaurant = null;
      budget = null;
      vegetarian = null;
      minutes = null;
      rating = null;
      previousBudgetNotice = null;
      _resetPagination();
    });
  }

  int get _activeFilterCount => [
    category,
    cuisine,
    restaurant,
    budget,
    vegetarian,
    minutes,
    rating,
  ].where((v) => v != null).length;

  Future<void> filters() async {
    final initial = (
      area: ref.read(deliveryServiceAreaProvider)!.id,
      category: category,
      cuisine: cuisine,
      restaurant: restaurant,
      budget: budget,
      vegetarian: vegetarian,
      minutes: minutes,
      rating: rating,
    );
    final result = await showModalBottomSheet<FilterSelection>(
      context: context,
      useRootNavigator: true,
      isScrollControlled: true,
      useSafeArea: true,
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * .94,
      ),
      sheetAnimationStyle: AnimationStyle(
        duration: motionDuration(context, 320),
        reverseDuration: motionDuration(context, 220),
      ),
      builder: (_) => SmartFilterSheet(initial),
    );
    if (result == null || !mounted) return;
    setState(() {
      category = result.category;
      cuisine = result.cuisine;
      restaurant = result.restaurant;
      budget = result.budget;
      vegetarian = result.vegetarian;
      minutes = result.minutes;
      rating = result.rating;
      previousBudgetNotice = null;
      _resetPagination();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final isOnline = !ref.watch(catalogRepositoryProvider).offline;

    ref.listen(deliveryServiceAreaProvider, (previous, next) {
      if (previous?.id != next?.id) {
        setState(() {
          previousBudgetNotice = null;
          _resetPagination();
        });
      }
    });
    // Final prices (fees, taxes) depend on the delivery service area of the
    // confirmed destination. Never fall back to a demo locality.
    final area = ref.watch(deliveryServiceAreaProvider);
    if (area == null) {
      return const ChooseDestinationPrompt(
        message: 'Smart Match shows final prices including delivery fees for your delivery address. Choose a delivery location inside a current service area to continue.',
      );
    }

    // Global Veg/Non-Veg/Both preference is the default; an explicit filter
    // choice in the sheet overrides it. Applied server-side on isVegetarian.
    final dietVeg = switch (ref.watch(dietPreferenceProvider)) {
      DietPreference.veg => true,
      DietPreference.nonVeg => false,
      DietPreference.both => null,
    };
    final query = (
      text: queryText,
      area: area.id,
      category: category,
      cuisine: cuisine,
      restaurant: restaurant,
      budget: budget,
      vegetarian: vegetarian ?? dietVeg,
      minutes: minutes,
      rating: rating,
      sort: sort,
      page: page,
    );

    ref.listen(smartSearchProvider(query), (_, next) {
      final pageData = next.asData?.value;
      if (pageData != null && mounted) {
        setState(() {
          _pageCache[pageData.page] = pageData.items;
          _lastKnownTotal = pageData.total;
        });
      }
    });

    final response = ref.watch(smartSearchProvider(query));
    final currentData = response.asData?.value;
    final visibleMeals = <SmartMeal>[
      for (var p = 1; p < page; p++) ...?_pageCache[p],
      ...?currentData?.items,
    ];
    final totalCount = currentData?.total ?? _lastKnownTotal;
    final isEmptyOnlineResult =
        page == 1 && currentData != null && currentData.items.isEmpty;
    final diagnosis = isOnline && isEmptyOnlineResult
        ? ref.watch(emptyDiagnosisProvider(query)).asData?.value
        : null;
    final categories = ref.watch(categoriesProvider).asData?.value ?? [];

    final minLoadedTotal = visibleMeals.isEmpty
        ? null
        : visibleMeals
              .map((m) => m.quote.total)
              .reduce((a, b) => a < b ? a : b);
    final bestValueId = sort == 'value' && visibleMeals.isNotEmpty
        ? visibleMeals.first.quote.dish.id
        : null;
    final hasAnyResettable = _activeFilterCount > 0 || queryText.isNotEmpty;

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                setState(() => _resetPagination());
                final refreshed = (
                  text: queryText,
                  area: area.id,
                  category: category,
                  cuisine: cuisine,
                  restaurant: restaurant,
                  budget: budget,
                  vegetarian: vegetarian ?? dietVeg,
                  minutes: minutes,
                  rating: rating,
                  sort: sort,
                  page: 1,
                );
                ref.invalidate(smartSearchProvider(refreshed));
                try {
                  await ref.read(smartSearchProvider(refreshed).future);
                } catch (_) {
                  /* Error UI handles retry cleanly. */
                }
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                children: [
                  const CatalogStatus(),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          'Good food, your budget.',
                          style: theme.textTheme.headlineMedium?.copyWith(
                            fontSize: 24,
                          ),
                        ),
                      ),
                      Badge(
                        isLabelVisible: _activeFilterCount > 0,
                        label: Text('$_activeFilterCount'),
                        child: IconButton.filledTonal(
                          tooltip: 'Meal filters',
                          onPressed: filters,
                          icon: const Icon(Icons.tune_rounded),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    key: const ValueKey('smart-search-input'),
                    controller: text,
                    textInputAction: TextInputAction.search,
                    onChanged: (value) {
                      debounce?.cancel();
                      setState(() {});
                      debounce = Timer(const Duration(milliseconds: 300), () {
                        if (mounted) {
                          setState(() {
                            queryText = value;
                            previousBudgetNotice = null;
                            _resetPagination();
                          });
                        }
                      });
                    },
                    onSubmitted: (_) =>
                        FocusManager.instance.primaryFocus?.unfocus(),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 12,
                      ),
                      hintText: 'Dish, kitchen or cuisine',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: text.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              onPressed: () {
                                debounce?.cancel();
                                text.clear();
                                setState(() {
                                  queryText = '';
                                  previousBudgetNotice = null;
                                  _resetPagination();
                                });
                              },
                              icon: const Icon(Icons.close),
                            ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  const DietSelector(),
                  const SizedBox(height: 10),
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        ActionChip(
                          avatar: const Icon(
                            Icons.location_on_outlined,
                            size: 16,
                          ),
                          label: Text(area.name),
                          onPressed: filters,
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: Text(
                            budget == null
                                ? 'Set a budget'
                                : 'Up to ₹${formatPaise(budget!)}',
                          ),
                          selected: budget != null,
                          onSelected: (_) => filters(),
                        ),
                        const SizedBox(width: 8),
                        FilterChip(
                          label: const Text('Vegetarian'),
                          selected: vegetarian == true,
                          onSelected: (v) => setState(() {
                            vegetarian = v ? true : null;
                            previousBudgetNotice = null;
                            _resetPagination();
                          }),
                        ),
                        if (minutes != null) ...[
                          const SizedBox(width: 8),
                          InputChip(
                            label: Text('Within $minutes min'),
                            onDeleted: () => setState(() {
                              minutes = null;
                              _resetPagination();
                            }),
                          ),
                        ],
                        if (category != null) ...[
                          const SizedBox(width: 8),
                          InputChip(
                            label: Text(
                              categories
                                      .where((c) => c.id == category)
                                      .firstOrNull
                                      ?.name ??
                                  category!,
                            ),
                            onDeleted: () => setState(() {
                              category = null;
                              _resetPagination();
                            }),
                          ),
                        ],
                        if (cuisine != null ||
                            restaurant != null ||
                            rating != null) ...[
                          const SizedBox(width: 8),
                          ActionChip(
                            label: const Text('More filters'),
                            onPressed: filters,
                          ),
                        ],
                        if (hasAnyResettable) ...[
                          const SizedBox(width: 4),
                          TextButton(
                            onPressed: resetAll,
                            child: const Text('Reset filters'),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (queryText.isEmpty &&
                      category == null &&
                      categories.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text('A starting point', style: theme.textTheme.labelSmall),
                    const SizedBox(height: 6),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          for (final c in categories.take(6))
                            Padding(
                              padding: const EdgeInsets.only(right: 8),
                              child: ActionChip(
                                label: Text(c.name),
                                onPressed: () => setState(() {
                                  category = c.id;
                                  _resetPagination();
                                }),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              currentData != null || visibleMeals.isNotEmpty
                                  ? '$totalCount ${totalCount == 1 ? 'meal' : 'meals'} in ${area.name}'
                                  : 'Searching ${area.name}...',
                              style: theme.textTheme.labelLarge,
                            ),
                            Text(
                              'Fees included · illustrative estimates',
                              style: theme.textTheme.bodySmall,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 168),
                        child: DropdownButtonFormField<String>(
                          key: ValueKey(sort),
                          initialValue: sort,
                          isExpanded: true,
                          style: theme.textTheme.labelLarge?.copyWith(
                            color: scheme.onSurface,
                          ),
                          decoration: const InputDecoration(
                            isDense: true,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: const [
                            DropdownMenuItem(
                              value: 'value',
                              child: Text('Best value'),
                            ),
                            DropdownMenuItem(
                              value: 'price',
                              child: Text('Lowest payable'),
                            ),
                            DropdownMenuItem(
                              value: 'time',
                              child: Text('Fastest'),
                            ),
                            DropdownMenuItem(
                              value: 'rating',
                              child: Text('Top rated'),
                            ),
                            DropdownMenuItem(
                              value: 'relevance',
                              child: Text('Best match'),
                            ),
                          ],
                          onChanged: (v) {
                            if (v == null || v == sort) return;
                            setState(() {
                              sort = v;
                              _resetPagination();
                            });
                          },
                        ),
                      ),
                    ],
                  ),
                  if (previousBudgetNotice != null) ...[
                    const SizedBox(height: 10),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: scheme.surfaceContainer,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: scheme.outlineVariant),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'Showing options above your previous ₹${formatPaise(previousBudgetNotice!)} budget.',
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                          TextButton(
                            style: TextButton.styleFrom(
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () => setState(() {
                              budget = previousBudgetNotice;
                              previousBudgetNotice = null;
                              _resetPagination();
                            }),
                            child: Text(
                              'Restore ₹${formatPaise(previousBudgetNotice!)}',
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  if (response.isLoading && visibleMeals.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    ),
                  if (response.hasError && visibleMeals.isEmpty)
                    QuoteFailure(
                      response.error!,
                      () => ref.invalidate(smartSearchProvider(query)),
                    ),
                  if (isEmptyOnlineResult ||
                      (!isOnline &&
                          page == 1 &&
                          currentData != null &&
                          currentData.items.isEmpty))
                    SmartEmptyState(
                      areaName: area.name,
                      queryText: queryText,
                      budget: budget,
                      maxMinutes: minutes,
                      diagnosis: diagnosis,
                      onResetFilters: resetFiltersOnly,
                      onResetAll: resetAll,
                      onOpenLocality: filters,
                      onIncreaseBudget: (cheapestPaise) => setState(() {
                        budget = cheapestPaise;
                        previousBudgetNotice = null;
                        _resetPagination();
                      }),
                      onViewAboveBudget: () => setState(() {
                        previousBudgetNotice = budget;
                        budget = null;
                        _resetPagination();
                      }),
                      onRemoveTimeLimit: () => setState(() {
                        minutes = null;
                        _resetPagination();
                      }),
                    ),
                  for (var idx = 0; idx < visibleMeals.length; idx++)
                    Builder(
                      builder: (context) {
                        final meal = visibleMeals[idx];
                        final info = buildCustomerExplanation(
                          meal,
                          index: idx,
                          pageTotal: totalCount,
                          minLoadedTotal: minLoadedTotal,
                          loadedCount: visibleMeals.length,
                          budget: budget,
                          vegetarian: vegetarian,
                          maxMinutes: minutes,
                          sort: sort,
                        );
                        return Reveal(
                          key: ValueKey(
                            '${meal.quote.dish.id}-${meal.quote.fingerprint}',
                          ),
                          child: SmartMealCard(
                            meal: meal,
                            badge: info.badge,
                            reason: info.reason,
                            comparing: selected.contains(meal.quote.dish.id),
                            onCompareToggle: (v) => setState(() {
                              if (!v) {
                                selected.remove(meal.quote.dish.id);
                              } else if (selected.length < 3) {
                                selected.add(meal.quote.dish.id);
                              } else {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(
                                    content: Text('Compare up to three meals.'),
                                  ),
                                );
                              }
                            }),
                          ),
                        );
                      },
                    ),
                  if (visibleMeals.isNotEmpty &&
                      visibleMeals.length < totalCount)
                    Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        children: [
                          Text(
                            'Showing ${visibleMeals.length} of $totalCount meals',
                            style: theme.textTheme.bodySmall,
                          ),
                          const SizedBox(height: 8),
                          if (response.isLoading)
                            const Padding(
                              padding: EdgeInsets.all(8),
                              child: CircularProgressIndicator(),
                            )
                          else
                            OutlinedButton(
                              onPressed: () => setState(() => page++),
                              child: Text(
                                'Show more meals (${totalCount - visibleMeals.length} remaining)',
                              ),
                            ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: motionDuration(context),
            child: selected.isEmpty
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton.icon(
                        onPressed: selected.length < 2
                            ? null
                            : () => showMealComparison(
                                context,
                                area.id,
                                selected.toList(),
                                bestValueDishId: bestValueId,
                              ),
                        icon: const Icon(Icons.compare_arrows),
                        label: Text('Compare ${selected.length} meals'),
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
}
