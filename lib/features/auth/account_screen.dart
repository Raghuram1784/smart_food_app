import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/design.dart';
import '../../core/providers.dart';
import '../navigation/workspace_provider.dart';
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
      ref
          .read(activeWorkspaceProvider.notifier)
          .setWorkspace(RoleWorkspace.customer);
      if (mounted) context.go('/');
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
            ? ListView(
                padding: const EdgeInsets.all(24),
                children: [
                  const SizedBox(height: 16),
                  Text(
                    'Your account',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 8),
                  const Text('Sign in to access your account.'),
                  const SizedBox(height: 20),
                  FilledButton(
                    onPressed: () => context.go('/login'),
                    child: const Text('Sign in'),
                  ),
                  const _AppearanceSection(),
                ],
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
                  if (session.user.roles.length > 1) ...[
                    const SizedBox(height: 12),
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Switch workspace',
                              style: Theme.of(context).textTheme.titleSmall,
                            ),
                            const SizedBox(height: 8),
                            Wrap(
                              spacing: 8,
                              runSpacing: 6,
                              children: [
                                if (session.user.roles.contains('CUSTOMER'))
                                  ChoiceChip(
                                    label: const Text('Customer Store'),
                                    selected:
                                        ref.watch(activeWorkspaceProvider) ==
                                        RoleWorkspace.customer,
                                    onSelected: (_) {
                                      ref
                                          .read(
                                            activeWorkspaceProvider.notifier,
                                          )
                                          .setWorkspace(RoleWorkspace.customer);
                                      context.go('/');
                                    },
                                  ),
                                if (session.user.roles.contains(
                                  'RESTAURANT_OWNER',
                                ))
                                  ChoiceChip(
                                    label: const Text('Restaurant Kitchen'),
                                    selected:
                                        ref.watch(activeWorkspaceProvider) ==
                                        RoleWorkspace.restaurantOwner,
                                    onSelected: (_) {
                                      ref
                                          .read(
                                            activeWorkspaceProvider.notifier,
                                          )
                                          .setWorkspace(
                                            RoleWorkspace.restaurantOwner,
                                          );
                                      context.go('/owner');
                                    },
                                  ),
                                if (session.user.roles.contains(
                                  'DELIVERY_PARTNER',
                                ))
                                  ChoiceChip(
                                    label: const Text('Delivery Partner'),
                                    selected:
                                        ref.watch(activeWorkspaceProvider) ==
                                        RoleWorkspace.deliveryPartner,
                                    onSelected: (_) {
                                      ref
                                          .read(
                                            activeWorkspaceProvider.notifier,
                                          )
                                          .setWorkspace(
                                            RoleWorkspace.deliveryPartner,
                                          );
                                      context.go('/deliveries');
                                    },
                                  ),
                                if (session.user.roles.contains('ADMIN'))
                                  ChoiceChip(
                                    label: const Text('Admin Dispatch'),
                                    selected:
                                        ref.watch(activeWorkspaceProvider) ==
                                        RoleWorkspace.admin,
                                    onSelected: (_) {
                                      ref
                                          .read(
                                            activeWorkspaceProvider.notifier,
                                          )
                                          .setWorkspace(RoleWorkspace.admin);
                                      context.go('/dispatch');
                                    },
                                  ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                  const _AppearanceSection(),
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

class _AppearanceSection extends ConsumerWidget {
  const _AppearanceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    final theme = Theme.of(context);
    final culinary = theme.extension<CulinaryColors>();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(height: 36),
        Text('A matter of taste', style: theme.textTheme.headlineSmall),
        const SizedBox(height: 6),
        Text(
          'Choose how your everyday looks.',
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
        const SizedBox(height: 16),
        for (final value in ThemeMode.values)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Material(
              color: mode == value
                  ? (culinary?.seaGlass ?? theme.colorScheme.primaryContainer)
                  : theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(16),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                ),
                title: Text(switch (value) {
                  ThemeMode.system => 'Match system',
                  ThemeMode.light => 'Light mode',
                  ThemeMode.dark => 'Dark mode',
                }),
                subtitle: Text(switch (value) {
                  ThemeMode.system => 'Follow your device setting',
                  ThemeMode.light => 'Warm paper, ink and terracotta accents',
                  ThemeMode.dark => 'Culinary noir with brass highlights',
                }),
                trailing: mode == value
                    ? const Icon(Icons.check_circle_rounded)
                    : null,
                onTap: () =>
                    ref.read(appearanceProvider.notifier).select(value),
              ),
            ),
          ),
      ],
    );
  }
}
