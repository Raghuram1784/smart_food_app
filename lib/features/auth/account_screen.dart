import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'auth_provider.dart';
import 'auth_repository.dart';

class AccountScreen extends ConsumerStatefulWidget {
  const AccountScreen({super.key});
  @override
  ConsumerState<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends ConsumerState<AccountScreen> {
  bool busy = false;
  String? error;
  Future<void> logout(bool all) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(authProvider.notifier).logout(all: all);
      if (mounted) context.go('/profile');
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editName(String current) async {
    final controller = TextEditingController(text: current);
    final result = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Your display name'),
        content: TextField(
          controller: controller,
          maxLength: 80,
          decoration: const InputDecoration(labelText: 'Name'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              if (controller.text.trim().length >= 2) {
                Navigator.pop(context, controller.text.trim());
              }
            },
            child: const Text('Save'),
          ),
        ],
      ),
    );
    // Controller disposal is deferred until the dialog's closing transition is complete.
    Future<void>.delayed(const Duration(seconds: 1), controller.dispose);
    if (result != null) {
      try {
        await ref.read(authProvider.notifier).updateName(result);
      } catch (e) {
        if (mounted) setState(() => error = authError(e));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = ref.watch(authProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Your account')),
      body: auth.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(authError(e)),
              TextButton(
                onPressed: () => ref.invalidate(authProvider),
                child: const Text('Retry session'),
              ),
            ],
          ),
        ),
        data: (session) => session == null
            ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Sign in to access your account.'),
                    FilledButton(
                      onPressed: () => context.go('/login'),
                      child: const Text('Sign in'),
                    ),
                  ],
                ),
              )
            : ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  Text(
                    session.user.name,
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(session.user.email),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final role in session.user.roles)
                        Chip(
                          label: Text(role.replaceAll('_', ' ').toLowerCase()),
                        ),
                    ],
                  ),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: () => editName(session.user.name),
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Edit display name'),
                    ),
                  ),
                  if (session.user.roles.contains('CUSTOMER')) ...[
                    ListTile(
                      onTap: () => context.push('/cart'),
                      leading: const Icon(Icons.shopping_bag_outlined),
                      title: const Text('Your cart'),
                    ),
                    ListTile(
                      onTap: () => context.push('/orders'),
                      leading: const Icon(Icons.receipt_long_outlined),
                      title: const Text('Your orders'),
                    ),
                    ListTile(
                      onTap: () => context.push('/addresses'),
                      leading: const Icon(Icons.location_on_outlined),
                      title: const Text('Delivery addresses'),
                    ),
                    const ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: Icon(Icons.person_outline),
                      title: Text('Customer account'),
                      subtitle: Text(
                        'Your cart and orders are saved to your account.',
                      ),
                    ),
                  ],
                  if (session.user.roles.contains('RESTAURANT_OWNER')) ...[
                    Text(
                      'Your restaurant memberships',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    if (session.user.restaurants.isEmpty)
                      const Text('No active restaurant memberships.'),
                    for (final restaurant in session.user.restaurants)
                      ListTile(
                        title: Text('${restaurant.name} · Incoming orders'),
                        leading: const Icon(Icons.receipt_long_outlined),
                        onTap: () => context.push('/inbox/${restaurant.id}'),
                      ),
                    for (final restaurant in session.user.restaurants)
                      AccountContext(
                        'restaurant/${restaurant.id}',
                        restaurant.name,
                      ),
                  ],
                  if (session.user.roles.contains('DELIVERY_PARTNER'))
                    FilledButton.tonal(
                      onPressed: () => context.push('/deliveries'),
                      child: const Text('Your deliveries'),
                    ),
                  if (session.user.roles.contains('ADMIN'))
                    FilledButton.tonal(
                      onPressed: () => context.push('/dispatch'),
                      child: const Text('Delivery dispatch'),
                    ),
                  const SizedBox(height: 24),
                  Text(
                    'Session expires ${session.expiresAt.toLocal()}.',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  if (error != null)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      child: Text(
                        error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: busy ? null : () => logout(false),
                    child: const Text('Sign out'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => logout(true),
                    child: const Text('Sign out on all devices'),
                  ),
                ],
              ),
      ),
    );
  }
}

class AccountContext extends ConsumerWidget {
  final String path, title;
  const AccountContext(this.path, this.title, {super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: ref
        .watch(accountContextProvider(path))
        .when(
          loading: () => const LinearProgressIndicator(),
          error: (e, _) => Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(authError(e)),
              TextButton(
                onPressed: () => ref.invalidate(accountContextProvider(path)),
                child: const Text('Retry access check'),
              ),
            ],
          ),
          data: (data) => ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.verified_user_outlined),
            title: Text(title),
            subtitle: Text(
              data['restaurant'] != null
                  ? 'Active owner membership · ${data['restaurant']['operatingStatus'].toString().toLowerCase()}. Restaurant operations are coming later.'
                  : data['notice'] as String,
            ),
          ),
        ),
  );
}
