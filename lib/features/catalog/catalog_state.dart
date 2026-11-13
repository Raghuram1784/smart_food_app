import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'catalog_repository.dart';

class CatalogStatus extends ConsumerWidget {
  const CatalogStatus({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 8),
    child: Text(
      ref.watch(catalogRepositoryProvider).offline
          ? 'Offline demo · bundled catalog'
          : 'Live catalog · sample data',
      style: Theme.of(context).textTheme.labelSmall,
    ),
  );
}

class CatalogFailure extends StatelessWidget {
  final Object error;
  final VoidCallback retry;
  const CatalogFailure(this.error, this.retry, {super.key});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(24),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.cloud_off_outlined, size: 36),
        const SizedBox(height: 12),
        Text(
          error is DioException &&
                  (error as DioException).response?.statusCode == 404
              ? 'This item is no longer in the catalog.'
              : 'The catalog is unavailable right now.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 8),
        const Text(
          'Check your connection and try again.',
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 12),
        OutlinedButton(onPressed: retry, child: const Text('Retry')),
      ],
    ),
  );
}
