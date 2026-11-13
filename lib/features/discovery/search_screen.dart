import 'smart_search_screen.dart';

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../catalog/catalog_repository.dart';
import '../catalog/catalog_state.dart';
import '../../shared/components.dart';

class SearchScreen extends ConsumerStatefulWidget {
  final String? initialCategory;
  final bool affordable;
  const SearchScreen({
    super.key,
    this.initialCategory,
    this.affordable = false,
  });
  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  final controller = TextEditingController();
  String? category;
  String queryText = '';
  int page = 1;
  Timer? debounce;
  late bool affordable;
  bool areaFilter = true;
  @override
  void initState() {
    super.initState();
    category = widget.initialCategory?.toLowerCase();
    affordable = widget.affordable;
  }

  @override
  void dispose() {
    debounce?.cancel();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!ref.watch(catalogRepositoryProvider).offline) {
      return SmartSearchScreen(
        initialCategory: widget.initialCategory,
        affordable: widget.affordable,
      );
    }
    final area = ref.watch(locationProvider);
    final query = (
      text: queryText,
      category: category,
      area: areaFilter ? area.id : null,
      affordable: affordable,
      page: page,
    );
    final response = ref.watch(catalogSearchProvider(query));
    final categoryResponse = ref.watch(categoriesProvider);
    final results = response.asData?.value.items ?? [];
    final kitchens = response.asData?.value.restaurants ?? [];
    return SafeArea(
      child: RefreshIndicator(
        onRefresh: () async {
          ref.invalidate(categoriesProvider);
          ref.invalidate(catalogSearchProvider(query));
          try {
            await ref.read(catalogSearchProvider(query).future);
          } catch (_) {
            /* Provider renders the error. */
          }
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            const CatalogStatus(),
            Text(
              'Find your next\nfavourite.',
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            TextField(
              controller: controller,
              onChanged: (_) {
                debounce?.cancel();
                setState(() {});
                debounce = Timer(const Duration(milliseconds: 300), () {
                  if (mounted) {
                    setState(() {
                      queryText = controller.text;
                      page = 1;
                    });
                  }
                });
              },
              decoration: InputDecoration(
                hintText: 'Dish, restaurant or cuisine',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: controller.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Clear search',
                        onPressed: () {
                          debounce?.cancel();
                          controller.clear();
                          setState(() {
                            queryText = '';
                            page = 1;
                          });
                        },
                        icon: const Icon(Icons.close),
                      ),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                ChoiceChip(
                  label: const Text('All'),
                  selected: category == null,
                  onSelected: (_) => setState(() {
                    category = null;
                    page = 1;
                  }),
                ),
                for (final c
                    in categoryResponse.asData?.value ?? <FoodCategory>[])
                  ChoiceChip(
                    label: Text(c.name),
                    selected: category == c.id,
                    onSelected: (selected) => setState(() {
                      category = selected ? c.id : null;
                      page = 1;
                    }),
                  ),
                FilterChip(
                  label: Text('In ${area.name}'),
                  selected: areaFilter,
                  onSelected: (v) => setState(() {
                    areaFilter = v;
                    page = 1;
                  }),
                ),
                FilterChip(
                  label: const Text('Under ₹250'),
                  selected: affordable,
                  onSelected: (v) => setState(() {
                    affordable = v;
                    page = 1;
                  }),
                ),
              ],
            ),
            if (categoryResponse.hasError)
              CatalogFailure(
                categoryResponse.error!,
                () => ref.invalidate(categoriesProvider),
              ),
            const SizedBox(height: 20),
            if (response.isLoading)
              const Center(child: CircularProgressIndicator()),
            if (response.hasError)
              CatalogFailure(
                response.error!,
                () => ref.invalidate(catalogSearchProvider(query)),
              ),
            if (response.hasValue)
              Text(
                '${response.asData?.value.total ?? 0} dishes · page $page',
                style: Theme.of(context).textTheme.labelMedium,
              ),
            if (response.hasValue && results.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 48),
                child: Column(
                  children: [
                    const Icon(Icons.search_off_rounded, size: 48),
                    const SizedBox(height: 20),
                    Text(
                      'A craving less ordinary?',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Try “pasta”, “Italian” or another category.',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    OutlinedButton(
                      onPressed: () {
                        debounce?.cancel();
                        controller.clear();
                        setState(() {
                          queryText = '';
                          page = 1;
                          category = null;
                          affordable = false;
                          areaFilter = true;
                        });
                      },
                      child: const Text('Reset search'),
                    ),
                  ],
                ),
              ),
            ...results.map(
              (d) => Column(
                children: [
                  DishTile(d),
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: () =>
                          context.push('/restaurant/${d.restaurantId}'),
                      child: const Text('Explore restaurant'),
                    ),
                  ),
                ],
              ),
            ),
            if (response.hasValue &&
                (page > 1 || page * 20 < response.asData!.value.total))
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  TextButton(
                    onPressed: page > 1 ? () => setState(() => page--) : null,
                    child: const Text('Previous'),
                  ),
                  TextButton(
                    onPressed: page * 20 < response.asData!.value.total
                        ? () => setState(() => page++)
                        : null,
                    child: const Text('Next'),
                  ),
                ],
              ),
            if (kitchens.isNotEmpty) ...[
              const SectionTitle('Matching kitchens'),
              ...kitchens.map(RestaurantCard.new),
            ],
          ],
        ),
      ),
    );
  }
}
