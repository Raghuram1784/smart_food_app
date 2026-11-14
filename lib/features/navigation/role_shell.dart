import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../auth/auth_provider.dart';
import '../commerce/commerce_widgets.dart';
import 'workspace_provider.dart';

class RoleShell extends ConsumerWidget {
  final Widget child;
  const RoleShell({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final workspace = ref.watch(activeWorkspaceProvider);
    String path = '/';
    String? tab;
    try {
      final state = GoRouterState.of(context);
      path = state.uri.path;
      tab = state.uri.queryParameters['tab'];
    } catch (_) {}

    final destinations = _destinationsFor(workspace);
    final selectedIndex = _selectedIndex(workspace, path, tab);

    return Scaffold(
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 840),
          child: child,
        ),
      ),
      floatingActionButton:
          workspace == RoleWorkspace.customer &&
              (path == '/' || path == '/search')
          ? const CartShortcut()
          : null,
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Sticky View Cart while browsing (server cart has items).
          if (workspace == RoleWorkspace.customer &&
              (path == '/' || path == '/search' || path == '/restaurants'))
            const ViewCartBar(),
          NavigationBar(
            selectedIndex: selectedIndex.clamp(0, destinations.length - 1),
            onDestinationSelected: (index) => _navigate(context, workspace, index),
            destinations: destinations,
          ),
        ],
      ),
    );
  }

  List<NavigationDestination> _destinationsFor(RoleWorkspace workspace) {
    switch (workspace) {
      case RoleWorkspace.restaurantOwner:
        return const [
          NavigationDestination(
            icon: Icon(Icons.dashboard_outlined),
            selectedIcon: Icon(Icons.dashboard_rounded),
            label: 'Dashboard',
          ),
          NavigationDestination(
            icon: Icon(Icons.notifications_active_outlined),
            selectedIcon: Icon(Icons.notifications_active_rounded),
            label: 'New Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.soup_kitchen_outlined),
            selectedIcon: Icon(Icons.soup_kitchen_rounded),
            label: 'Kitchen',
          ),
          NavigationDestination(
            icon: Icon(Icons.history_outlined),
            selectedIcon: Icon(Icons.history_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.store_outlined),
            selectedIcon: Icon(Icons.store_rounded),
            label: 'Account',
          ),
        ];

      case RoleWorkspace.deliveryPartner:
        return const [
          NavigationDestination(
            icon: Icon(Icons.assignment_outlined),
            selectedIcon: Icon(Icons.assignment_rounded),
            label: 'Assigned',
          ),
          NavigationDestination(
            icon: Icon(Icons.two_wheeler_outlined),
            selectedIcon: Icon(Icons.two_wheeler_rounded),
            label: 'In Transit',
          ),
          NavigationDestination(
            icon: Icon(Icons.fact_check_outlined),
            selectedIcon: Icon(Icons.fact_check_rounded),
            label: 'History',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ];

      case RoleWorkspace.admin:
        return const [
          NavigationDestination(
            icon: Icon(Icons.alt_route_outlined),
            selectedIcon: Icon(Icons.alt_route_rounded),
            label: 'Dispatch',
          ),
          NavigationDestination(
            icon: Icon(Icons.pending_actions_outlined),
            selectedIcon: Icon(Icons.pending_actions_rounded),
            label: 'Unassigned',
          ),
          NavigationDestination(
            icon: Icon(Icons.groups_outlined),
            selectedIcon: Icon(Icons.groups_rounded),
            label: 'Riders',
          ),
          NavigationDestination(
            icon: Icon(Icons.admin_panel_settings_outlined),
            selectedIcon: Icon(Icons.admin_panel_settings_rounded),
            label: 'Account',
          ),
        ];

      case RoleWorkspace.customer:
        return const [
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: Icon(Icons.search_outlined),
            selectedIcon: Icon(Icons.search_rounded),
            label: 'Search',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag_outlined),
            selectedIcon: Icon(Icons.shopping_bag_rounded),
            label: 'Cart',
          ),
          NavigationDestination(
            icon: Icon(Icons.receipt_long_outlined),
            selectedIcon: Icon(Icons.receipt_long_rounded),
            label: 'My Orders',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outline),
            selectedIcon: Icon(Icons.person),
            label: 'Account',
          ),
        ];
    }
  }

  int _selectedIndex(RoleWorkspace workspace, String path, String? tab) {
    switch (workspace) {
      case RoleWorkspace.restaurantOwner:
        if (path == '/account' || path == '/profile') return 4;
        if (tab == 'history') return 3;
        if (tab == 'kitchen') return 2;
        if (tab == 'new') return 1;
        return 0;

      case RoleWorkspace.deliveryPartner:
        if (path == '/account' || path == '/profile') return 3;
        if (tab == 'history') return 2;
        if (tab == 'active') return 1;
        return 0;

      case RoleWorkspace.admin:
        if (path == '/account' || path == '/profile') return 3;
        if (tab == 'riders') return 2;
        if (tab == 'unassigned') return 1;
        return 0;

      case RoleWorkspace.customer:
        if (path == '/account' || path == '/profile') return 4;
        if (path == '/orders') return 3;
        if (path == '/cart') return 2;
        if (path == '/search') return 1;
        return 0;
    }
  }

  void _navigate(BuildContext context, RoleWorkspace workspace, int index) {
    switch (workspace) {
      case RoleWorkspace.restaurantOwner:
        switch (index) {
          case 0:
            context.go('/owner');
            break;
          case 1:
            context.go('/owner?tab=new');
            break;
          case 2:
            context.go('/owner?tab=kitchen');
            break;
          case 3:
            context.go('/owner?tab=history');
            break;
          case 4:
            context.go('/account');
            break;
        }
        break;

      case RoleWorkspace.deliveryPartner:
        switch (index) {
          case 0:
            context.go('/deliveries?tab=assigned');
            break;
          case 1:
            context.go('/deliveries?tab=active');
            break;
          case 2:
            context.go('/deliveries?tab=history');
            break;
          case 3:
            context.go('/account');
            break;
        }
        break;

      case RoleWorkspace.admin:
        switch (index) {
          case 0:
            context.go('/dispatch?tab=all');
            break;
          case 1:
            context.go('/dispatch?tab=unassigned');
            break;
          case 2:
            context.go('/dispatch?tab=riders');
            break;
          case 3:
            context.go('/account');
            break;
        }
        break;

      case RoleWorkspace.customer:
        switch (index) {
          case 0:
            context.go('/');
            break;
          case 1:
            context.go('/search');
            break;
          case 2:
            context.go('/cart');
            break;
          case 3:
            context.go('/orders');
            break;
          case 4:
            context.go('/account');
            break;
        }
        break;
    }
  }
}

class WorkspaceSwitcherBar extends ConsumerWidget
    implements PreferredSizeWidget {
  final String title;
  final List<Widget>? actions;

  const WorkspaceSwitcherBar({super.key, required this.title, this.actions});

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(authProvider).asData?.value;
    final user = session?.user;
    final roles = user?.roles ?? [];

    final hasMultipleRoles = roles.length > 1;

    return AppBar(
      title: Text(title),
      actions: [
        if (hasMultipleRoles)
          PopupMenuButton<RoleWorkspace>(
            tooltip: 'Switch workspace',
            icon: const Icon(Icons.swap_horiz_rounded),
            onSelected: (workspace) {
              ref
                  .read(activeWorkspaceProvider.notifier)
                  .setWorkspace(workspace);
              context.go(homeRouteForWorkspace(workspace, user));
            },
            itemBuilder: (context) => [
              if (roles.contains('CUSTOMER'))
                const PopupMenuItem(
                  value: RoleWorkspace.customer,
                  child: ListTile(
                    leading: Icon(Icons.explore_outlined),
                    title: Text('Customer Storefront'),
                  ),
                ),
              if (roles.contains('RESTAURANT_OWNER'))
                const PopupMenuItem(
                  value: RoleWorkspace.restaurantOwner,
                  child: ListTile(
                    leading: Icon(Icons.store_outlined),
                    title: Text('Restaurant Kitchen'),
                  ),
                ),
              if (roles.contains('DELIVERY_PARTNER'))
                const PopupMenuItem(
                  value: RoleWorkspace.deliveryPartner,
                  child: ListTile(
                    leading: Icon(Icons.delivery_dining_outlined),
                    title: Text('Delivery Partner'),
                  ),
                ),
              if (roles.contains('ADMIN'))
                const PopupMenuItem(
                  value: RoleWorkspace.admin,
                  child: ListTile(
                    leading: Icon(Icons.admin_panel_settings_outlined),
                    title: Text('Admin Dispatch'),
                  ),
                ),
            ],
          ),
        ...?actions,
      ],
    );
  }
}
