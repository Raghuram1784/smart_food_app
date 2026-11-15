import 'features/tracking/track_order_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/design.dart';
import 'core/motion.dart';
import 'core/providers.dart';
import 'features/auth/account_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/commerce/address_screen.dart';
import 'features/commerce/cart_screen.dart';
import 'features/commerce/commerce_widgets.dart';
import 'features/commerce/operations_screen.dart';
import 'features/commerce/orders_screen.dart';
import 'features/discovery/home_screen.dart';
import 'features/discovery/search_screen.dart';
import 'features/commerce/customer_otp_layer.dart';
import 'features/navigation/role_shell.dart';
import 'features/navigation/workspace_provider.dart';
import 'features/operations/owner_dashboard_screen.dart';
import 'features/operations/rider_dashboard_screen.dart';
import 'features/restaurant/restaurant_screen.dart';
import 'features/finder/finder_screen.dart';
import 'features/group/group_screens.dart';
import 'features/group/owner_group_proposals_screen.dart';

GoRouter createRouter([WidgetRef? ref]) => GoRouter(
  initialLocation: '/',
  redirect: (context, state) {
    if (ref == null) return null;
    final workspace = ref.read(activeWorkspaceProvider);

    // If an operational user lands on root '/', redirect them to their active workspace
    if (state.uri.path == '/') {
      if (workspace == RoleWorkspace.restaurantOwner) return '/owner';
      if (workspace == RoleWorkspace.deliveryPartner) return '/deliveries';
      if (workspace == RoleWorkspace.admin) return '/dispatch';
    }
    // Profile redirects to account for consistent role-based account view
    if (state.uri.path == '/profile') {
      return '/account';
    }
    return null;
  },
  routes: [
    ShellRoute(
      builder: (context, state, child) => RoleShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(path: '/restaurants', builder: (context, state) => const AllRestaurantsScreen()),
        GoRoute(
          path: '/search',
          builder: (context, state) => SearchScreen(
            key: ValueKey(state.uri.toString()),
            initialCategory: state.uri.queryParameters['category'],
            affordable: state.uri.queryParameters['affordable'] == 'true',
          ),
        ),
        GoRoute(
          path: '/cart',
          builder: (context, state) => const CommerceGate(child: CartScreen()),
        ),
        GoRoute(
          path: '/orders',
          builder: (context, state) =>
              const CommerceGate(child: OrdersScreen()),
        ),
        GoRoute(
          path: '/account',
          pageBuilder: (context, state) =>
              editorialPage(context, state, const AccountScreen()),
        ),
        GoRoute(
          path: '/owner',
          builder: (context, state) => CommerceGate(
            role: 'RESTAURANT_OWNER',
            child: OwnerDashboardScreen(
              restaurantId: state.uri.queryParameters['restaurantId'],
              initialTab: state.uri.queryParameters['tab'] ?? 'all',
            ),
          ),
        ),
        GoRoute(
          path: '/deliveries',
          builder: (context, state) => CommerceGate(
            role: 'DELIVERY_PARTNER',
            child: RiderDashboardScreen(
              tab: state.uri.queryParameters['tab'],
            ),
          ),
        ),
        GoRoute(
          path: '/dispatch',
          builder: (context, state) => CommerceGate(
            role: 'ADMIN',
            child: OperationsScreen(
              scope: 'dispatch',
              tab: state.uri.queryParameters['tab'],
            ),
          ),
        ),
      ],
    ),
    // Full screen routes pushed over shell:
    GoRoute(path: '/groups', builder: (context, state) => const CommerceGate(child: GroupHubScreen())),
    GoRoute(
      path: '/groups/:id',
      builder: (context, state) => CommerceGate(child: GroupRoomScreen(groupId: state.pathParameters['id']!, showInvite: state.uri.queryParameters['invite'] == '1', showPeople: state.uri.queryParameters['friends'] == '1')),
    ),
    // Shareable invite link: <APP_LINK_BASE>/group/<token> (sign-in first, then join).
    GoRoute(path: '/group/:token', builder: (context, state) => CommerceGate(child: GroupJoinLinkScreen(token: state.pathParameters['token']!))),
    GoRoute(
      path: '/owner/group-proposals',
      builder: (context, state) => CommerceGate(role: 'RESTAURANT_OWNER', child: OwnerGroupProposalsScreen(restaurantId: state.uri.queryParameters['restaurantId'])),
    ),
    GoRoute(
      path: '/finder',
      builder: (context, state) => CommerceGate(child: FinderScreen(initialPrompt: state.uri.queryParameters['q'])),
    ),
    GoRoute(
      path: '/addresses',
      builder: (context, state) => const CommerceGate(child: AddressScreen()),
    ),
    GoRoute(
      path: '/checkout',
      builder: (context, state) => CommerceGate(
        child: CheckoutScreen(
          quote: state.extra is Map<String, dynamic>
              ? state.extra as Map<String, dynamic>
              : null,
        ),
      ),
    ),
    GoRoute(
      path: '/orders/:id',
      builder: (context, state) => CommerceGate(
        child: OrderDetailScreen(
          id: state.pathParameters['id']!,
          placed: state.uri.queryParameters['placed'] == 'true',
        ),
      ),
    ),
    GoRoute(
      path: '/orders/:id/track',
      builder: (context, state) => CommerceGate(child: TrackOrderScreen(orderId: state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/inbox/:id',
      builder: (context, state) => CommerceGate(
        role: 'RESTAURANT_OWNER',
        child: OwnerDashboardScreen(
          restaurantId: state.pathParameters['id']!,
          initialTab: state.uri.queryParameters['tab'] ?? 'all',
        ),
      ),
    ),
    GoRoute(
      path: '/inbox/:id/orders/:orderId',
      builder: (context, state) => CommerceGate(
        role: 'RESTAURANT_OWNER',
        child: OperationsScreen(
          scope: 'restaurant',
          orderId: state.pathParameters['orderId']!,
        ),
      ),
    ),
    GoRoute(
      path: '/login',
      pageBuilder: (context, state) =>
          editorialPage(context, state, const LoginScreen()),
    ),
    GoRoute(
      path: '/restaurant/:id',
      pageBuilder: (context, state) => editorialPage(
        context,
        state,
        RestaurantScreen(id: state.pathParameters['id']!),
      ),
    ),
  ],
  errorBuilder: (context, state) => Scaffold(
    body: Center(
      child: FilledButton(
        onPressed: () => context.go('/'),
        child: const Text('Return to discovery'),
      ),
    ),
  ),
);

class FoodApp extends ConsumerStatefulWidget {
  const FoodApp({super.key});
  @override
  ConsumerState<FoodApp> createState() => _FoodAppState();
}

class _FoodAppState extends ConsumerState<FoodApp> {
  late final router = createRouter(ref);
  @override
  void dispose() {
    router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: Brand.name,
    debugShowCheckedModeBanner: false,
    theme: appTheme(Brightness.light),
    darkTheme: appTheme(Brightness.dark),
    themeMode: ref.watch(appearanceProvider),
    themeAnimationDuration: MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 220),
    routerConfig: router,
    // One global customer OTP layer above every route (customer accounts only).
    builder: (context, child) => CustomerOtpLayer(
      // The popup is inserted into this root Navigator's Overlay, not built here.
      navigatorKey: router.routerDelegate.navigatorKey,
      onOpenOrder: (id) => router.push('/orders/$id'),
      child: child ?? const SizedBox.shrink(),
    ),
  );
}
