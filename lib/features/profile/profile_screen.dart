import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';

import '../../core/providers.dart';
import '../../core/design.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final mode = ref.watch(appearanceProvider);
    final session = ref.watch(authProvider).asData?.value;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Text(
            'Make yourself\nat home.',
            style: Theme.of(context).textTheme.headlineLarge,
          ),
          const SizedBox(height: 32),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: CircleAvatar(
              radius: 28,
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .surfaceContainerHigh,
              child: const Icon(Icons.person_outline),
            ),
            title: Text(session?.user.name ?? 'Your account'),
            subtitle: Text(
              session?.user.email ??
                  'Sign in · browsing stays open to everyone',
            ),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => context.push(session == null ? '/login' : '/account'),
          ),
          const SizedBox(height: 32),
          Text(
            'A matter of taste',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 8),
          const Text('Choose how your everyday looks.'),
          const SizedBox(height: 20),
          for (final value in ThemeMode.values)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: mode == value
                    ? Theme.of(context).extension<CulinaryColors>()!.seaGlass
                    : Theme.of(context).colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(18),
                  ),
                  minVerticalPadding: 20,
                  leading: Icon(switch (value) {
                    ThemeMode.system => Icons.brightness_auto_outlined,
                    ThemeMode.light => Icons.light_mode_outlined,
                    ThemeMode.dark => Icons.dark_mode_outlined,
                  }),
                  title: Text(switch (value) {
                    ThemeMode.system => 'System default',
                    ThemeMode.light => 'Light mode',
                    ThemeMode.dark => 'Dark mode',
                  }),
                  subtitle: Text(switch (value) {
                    ThemeMode.system => 'Follow your device',
                    ThemeMode.light => 'Modern editorial food',
                    ThemeMode.dark => 'Culinary noir',
                  }),
                  trailing: Icon(
                    mode == value
                        ? Icons.radio_button_checked
                        : Icons.radio_button_unchecked,
                  ),
                  onTap: () async {
                    final saved = await ref
                        .read(appearanceProvider.notifier)
                        .select(value);
                    if (!saved && context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Could not save appearance. Please try again.',
                          ),
                        ),
                      );
                    }
                  },
                ),
              ),
            ),
          const SizedBox(height: 28),
          Text(Brand.name, style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          const Text(
            'A thoughtfully curated Hyderabad marketplace demo.\nKitchens, ratings, prices and delivery estimates are illustrative. Demo orders are recorded; no real payment is collected.',
          ),
          const SizedBox(height: 20),
          TextButton(
            onPressed: () =>
                showLicensePage(context: context, applicationName: Brand.name),
            child: const Text('Open-source licences'),
          ),
        ],
      ),
    );
  }
}
