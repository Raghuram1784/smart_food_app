import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../shared/components.dart';
import '../catalog/catalog.dart';
import '../catalog/catalog_repository.dart';

class HomeCategories extends StatelessWidget {
  final List<FoodCategory> categories;
  const HomeCategories(this.categories, {super.key});
  @override
  Widget build(BuildContext context) {
    final labelHeight = MediaQuery.textScalerOf(context).scale(12) * 1.5;
    return SizedBox(
      height: 84 + labelHeight * 2,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: categories.length,
        separatorBuilder: (_, index) => const SizedBox(width: 16),
        itemBuilder: (context, index) {
          final entry = categories[index];
          return InkWell(
            borderRadius: BorderRadius.circular(18),
            onTap: () => context.go('/search?category=${entry.id}'),
            child: SizedBox(
              width: 88 * MediaQuery.textScalerOf(context).scale(12) / 12,
              child: Column(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(22),
                    child: FoodPhoto(
                      entry.image,
                      folder: 'categories',
                      height: 72,
                      width: 72,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    entry.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.labelLarge,
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class EditorialFeature extends StatelessWidget {
  final Restaurant restaurant;
  const EditorialFeature(this.restaurant, {super.key});
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.extension<CulinaryColors>()!.peach,
      borderRadius: BorderRadius.circular(24),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/restaurant/${restaurant.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            FoodPhoto(
              restaurant.image,
              folder: restaurant.image == 'dosa' || restaurant.image == 'pizza'
                  ? 'hero'
                  : 'restaurants',
              height: 176,
              width: double.infinity,
            ),
            Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'THE LOCAL FAVOURITES EDIT',
                    style: theme.textTheme.labelSmall?.copyWith(
                      letterSpacing: 1.3,
                      color: theme.colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Crisp edges.\nComfort at heart.',
                    style: theme.textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${restaurant.name} · ${restaurant.time}',
                          style: theme.textTheme.labelMedium,
                        ),
                      ),
                      const Icon(Icons.arrow_outward, size: 22),
                    ],
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
