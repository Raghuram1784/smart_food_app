import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/providers.dart';
import '../navigation/workspace_provider.dart';
import 'auth_provider.dart';
import 'auth_repository.dart';

class _DemoRestaurantItem {
  final String id;
  final String name;
  final String locality;
  final String ownerEmail;

  const _DemoRestaurantItem({
    required this.id,
    required this.name,
    required this.locality,
    required this.ownerEmail,
  });

  factory _DemoRestaurantItem.fromJson(Map<String, dynamic> j) =>
      _DemoRestaurantItem(
        id: j['restaurantId'] as String? ?? '',
        name: j['restaurantName'] as String? ?? '',
        locality: j['localityName'] as String? ?? '',
        ownerEmail: j['ownerEmail'] as String? ?? '',
      );
}

const _kProvisionedDemoRestaurants = <_DemoRestaurantItem>[
  _DemoRestaurantItem(id: 'banjara-courtyard', name: 'Banjara Courtyard', locality: 'Banjara Hills', ownerEmail: 'banjara-courtyard.owner@demo.test'),
  _DemoRestaurantItem(id: 'begum-chaat-ameerpet', name: 'Begum Chaat Corner', locality: 'Ameerpet', ownerEmail: 'begum-chaat-ameerpet.owner@demo.test'),
  _DemoRestaurantItem(id: 'botanical-bowl-madhapur', name: 'Botanical Bowl Co.', locality: 'Madhapur', ownerEmail: 'botanical-bowl-madhapur.owner@demo.test'),
  _DemoRestaurantItem(id: 'bun', name: 'Bun & Beyond', locality: 'Jubilee Hills', ownerEmail: 'bun.owner@demo.test'),
  _DemoRestaurantItem(id: 'chaat-mandi-kondapur', name: 'Chaat Mandi', locality: 'Kondapur', ownerEmail: 'chaat.owner@demo.test'),
  _DemoRestaurantItem(id: 'charcoal-hitec', name: 'Charcoal Courtyard', locality: 'Hitec City', ownerEmail: 'charcoal-hitec.owner@demo.test'),
  _DemoRestaurantItem(id: 'clock-tower-secund', name: 'Clock Tower Kitchen', locality: 'Secunderabad', ownerEmail: 'clock-tower-secund.owner@demo.test'),
  _DemoRestaurantItem(id: 'crunch-box-kuka', name: 'KPHB Crunch Box', locality: 'Kukatpally', ownerEmail: 'crunch-box-kuka.owner@demo.test'),
  _DemoRestaurantItem(id: 'cyberabad-wok-madhapur', name: 'Cyberabad Wok', locality: 'Madhapur', ownerEmail: 'cyberabad-wok-madhapur.owner@demo.test'),
  _DemoRestaurantItem(id: 'dakshin-sunrise-secund', name: 'Dakshin Sunrise', locality: 'Secunderabad', ownerEmail: 'dakshin-sunrise-secund.owner@demo.test'),
  _DemoRestaurantItem(id: 'deccan-handi-gachi', name: 'Deccan Handi & Dum', locality: 'Gachibowli', ownerEmail: 'restaurant@demo.test'),
  _DemoRestaurantItem(id: 'deccan-leaf-ameerpet', name: 'Deccan Leaf Thali', locality: 'Ameerpet', ownerEmail: 'deccan-leaf-ameerpet.owner@demo.test'),
  _DemoRestaurantItem(id: 'fd-smash-gachi', name: 'Financial District Smash', locality: 'Financial District', ownerEmail: 'fd-smash-gachi.owner@demo.test'),
  _DemoRestaurantItem(id: 'gachibowli-tiffin', name: 'Gachibowli Tiffin Co.', locality: 'Gachibowli', ownerEmail: 'gachibowli-tiffin.owner@demo.test'),
  _DemoRestaurantItem(id: 'golconda-zafran-mehdi', name: 'Golconda Zafran Biryani', locality: 'Mehdipatnam', ownerEmail: 'golconda-zafran-mehdi.owner@demo.test'),
  _DemoRestaurantItem(id: 'hearth', name: 'Hearth & Crust', locality: 'Hitec City', ownerEmail: 'hearth.owner@demo.test'),
  _DemoRestaurantItem(id: 'irani-bakery-mehdi', name: 'Mehdipatnam Irani Bakery', locality: 'Mehdipatnam', ownerEmail: 'irani-bakery-mehdi.owner@demo.test'),
  _DemoRestaurantItem(id: 'kaveri-veg-biryani-kuka', name: 'Kaveri Veg Biryani House', locality: 'Kukatpally', ownerEmail: 'kaveri-veg-biryani-kuka.owner@demo.test'),
  _DemoRestaurantItem(id: 'kesar-clove-jubilee', name: 'Kesar & Clove', locality: 'Jubilee Hills', ownerEmail: 'kesar-clove-jubilee.owner@demo.test'),
  _DemoRestaurantItem(id: 'koyla-seekh-banjara', name: 'Koyla & Seekh', locality: 'Banjara Hills', ownerEmail: 'koyla-seekh-banjara.owner@demo.test'),
  _DemoRestaurantItem(id: 'oven-crumb-kondapur', name: 'Oven & Crumb Bakehouse', locality: 'Kondapur', ownerEmail: 'oven-crumb-kondapur.owner@demo.test'),
  _DemoRestaurantItem(id: 'pind-handi-madhapur', name: 'Pind Di Handi', locality: 'Madhapur', ownerEmail: 'pind-handi-madhapur.owner@demo.test'),
  _DemoRestaurantItem(id: 'prana-bowls-jubilee', name: 'Prana Greens & Bowls', locality: 'Jubilee Hills', ownerEmail: 'prana-bowls-jubilee.owner@demo.test'),
  _DemoRestaurantItem(id: 'suprabhat-tiffins-kuka', name: 'Suprabhat Tiffins & Meals', locality: 'Kukatpally', ownerEmail: 'suprabhat-tiffins-kuka.owner@demo.test'),
  _DemoRestaurantItem(id: 'table', name: 'The Green Table', locality: 'Jubilee Hills', ownerEmail: 'table.owner@demo.test'),
  _DemoRestaurantItem(id: 'tiffin', name: 'The Tiffin Room', locality: 'Madhapur', ownerEmail: 'tiffin.owner@demo.test'),
  _DemoRestaurantItem(id: 'woodstone-hitec', name: 'Woodstone Napoli', locality: 'Hitec City', ownerEmail: 'woodstone-hitec.owner@demo.test'),
  _DemoRestaurantItem(id: 'zafran-mithai-jubilee', name: 'Zafran & Mithai', locality: 'Jubilee Hills', ownerEmail: 'zafran-mithai-jubilee.owner@demo.test'),
];

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidden = true, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(email.text, password.text);
      password.clear();
      if (mounted) {
        final session = ref.read(authProvider).asData?.value;
        final user = session?.user;
        ref.read(activeWorkspaceProvider.notifier).resetToDefault();

        final returnParam = GoRouterState.of(context)
            .uri
            .queryParameters['return'];
        if (returnParam == 'back' && context.canPop()) {
          context.pop();
        } else {
          final workspace = ref.read(activeWorkspaceProvider);
          final destination = homeRouteForWorkspace(workspace, user);
          context.go(destination);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _openRestaurantSelector() async {
    final selected = await showModalBottomSheet<_DemoRestaurantItem>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (ctx) => _RestaurantOwnerSelectorSheet(
        onSelect: (item) => Navigator.of(ctx).pop(item),
      ),
    );
    if (selected != null && mounted) {
      setState(() {
        email.text = selected.ownerEmail;
        password.clear();
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Selected ${selected.name} (${selected.ownerEmail})'),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your account')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'A familiar\nplace to return.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in to your account. Food discovery stays open to everyone.',
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const ValueKey('login-email'),
                      controller: email,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          v == null ||
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v.trim())
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('login-password'),
                      controller: password,
                      enabled: !busy,
                      obscureText: hidden,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: hidden ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password.'
                          : null,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      const Text(
                        'Development accounts',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final item in const {
                            'Customer': 'customer@demo.test',
                            'The Tiffin Room': 'tiffin.owner@demo.test',
                            'Deccan Handi': 'restaurant@demo.test',
                            'Chaat Mandi': 'chaat.owner@demo.test',
                            'Delivery partner': 'rider@demo.test',
                            'Administrator': 'admin@demo.test',
                          }.entries)
                            ActionChip(
                              avatar: item.key.contains('Tiffin') ||
                                      item.key.contains('Handi') ||
                                      item.key.contains('Chaat')
                                  ? const Icon(Icons.storefront, size: 16)
                                  : null,
                              label: Text(item.key),
                              onPressed: busy
                                  ? null
                                  : () {
                                      setState(() {
                                        email.text = item.value;
                                        password.clear();
                                      });
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        icon: const Icon(Icons.storefront_outlined),
                        label: const Text('Search all 28 restaurant kitchens…'),
                        onPressed: busy ? null : _openRestaurantSelector,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Email shortcuts only. Use the locally configured demo password.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Continue exploring'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RestaurantOwnerSelectorSheet extends ConsumerStatefulWidget {
  final ValueChanged<_DemoRestaurantItem> onSelect;
  const _RestaurantOwnerSelectorSheet({required this.onSelect});

  @override
  ConsumerState<_RestaurantOwnerSelectorSheet> createState() =>
      _RestaurantOwnerSelectorSheetState();
}

class _RestaurantOwnerSelectorSheetState
    extends ConsumerState<_RestaurantOwnerSelectorSheet> {
  final TextEditingController _searchController = TextEditingController();
  List<_DemoRestaurantItem> _items = _kProvisionedDemoRestaurants;
  String _filter = '';
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _fetchLiveRestaurants();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchLiveRestaurants() async {
    setState(() => _loading = true);
    try {
      final dio = ref.read(apiClientProvider);
      final response =
          await dio.get<Map<String, dynamic>>('auth/demo-restaurants');
      final data = response.data?['data'] ?? response.data;
      if (data is List && data.isNotEmpty) {
        final parsed = data
            .map(
              (j) => _DemoRestaurantItem.fromJson(
                Map<String, dynamic>.from(j as Map),
              ),
            )
            .toList();
        if (mounted) {
          setState(() {
            _items = parsed;
            _loading = false;
          });
        }
        return;
      }
    } catch (_) {
      // Graceful fallback to _kProvisionedDemoRestaurants
    }
    if (mounted) {
      setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final query = _filter.trim().toLowerCase();
    final filtered = query.isEmpty
        ? _items
        : _items.where((r) {
            return r.name.toLowerCase().contains(query) ||
                r.locality.toLowerCase().contains(query) ||
                r.ownerEmail.toLowerCase().contains(query);
          }).toList();

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: scheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: scheme.outlineVariant,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Select Restaurant Owner',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${_items.length} provisioned kitchens (active owners)',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: scheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_loading)
                      const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  autofocus: true,
                  decoration: InputDecoration(
                    prefixIcon: const Icon(Icons.search),
                    hintText: 'Search kitchen (e.g. Tiffin, Deccan, Chaat)...',
                    suffixIcon: _filter.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear),
                            onPressed: () {
                              _searchController.clear();
                              setState(() => _filter = '');
                            },
                          )
                        : null,
                    filled: true,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                  ),
                  onChanged: (v) => setState(() => _filter = v),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Text(
                          'No kitchen matches "$_filter"',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.outline,
                          ),
                        ),
                      )
                    : ListView.separated(
                        controller: scrollController,
                        itemCount: filtered.length,
                        separatorBuilder: (_, _) => const Divider(height: 1),
                        itemBuilder: (context, i) {
                          final item = filtered[i];
                          return ListTile(
                            leading: CircleAvatar(
                              backgroundColor: scheme.primaryContainer,
                              child: Icon(
                                Icons.restaurant,
                                color: scheme.onPrimaryContainer,
                                size: 20,
                              ),
                            ),
                            title: Text(
                              item.name,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600),
                            ),
                            subtitle: Text(
                              '${item.locality.isNotEmpty ? "${item.locality} · " : ""}${item.ownerEmail}',
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                            trailing:
                                const Icon(Icons.chevron_right, size: 20),
                            onTap: () => widget.onSelect(item),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
