import 'features/commerce/operations_screen.dart';
import 'core/motion.dart';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/design.dart';
import 'core/providers.dart';
import 'features/discovery/home_screen.dart';
import 'features/discovery/search_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/account_screen.dart';
import 'features/restaurant/restaurant_screen.dart';
import 'features/commerce/cart_screen.dart';
import 'features/commerce/address_screen.dart';
import 'features/commerce/orders_screen.dart';
import 'features/commerce/commerce_widgets.dart';

GoRouter createRouter() => GoRouter(
  routes: [
    GoRoute(
      path: '/dispatch',
      builder: (_, _) => const CommerceGate(
        role: 'ADMIN',
        child: OperationsScreen(scope: 'dispatch'),
      ),
    ),
    GoRoute(
      path: '/deliveries',
      builder: (_, _) => const CommerceGate(
        role: 'DELIVERY_PARTNER',
        child: OperationsScreen(scope: 'delivery'),
      ),
    ),
    GoRoute(
      path: '/cart',
      builder: (context, state) => const CommerceGate(child: CartScreen()),
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
      path: '/orders',
      builder: (context, state) => const CommerceGate(child: OrdersScreen()),
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
      path: '/inbox/:id',
      builder: (context, state) => CommerceGate(
        role: 'RESTAURANT_OWNER',
        child: OrdersScreen(restaurantId: state.pathParameters['id']!),
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
      path: '/account',
      pageBuilder: (context, state) =>
          editorialPage(context, state, const AccountScreen()),
    ),
    ShellRoute(
      builder: (context, state, child) => Scaffold(
        floatingActionButton: const CartShortcut(),
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: child,
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: state.uri.path == '/profile'
              ? 2
              : state.uri.path == '/search'
              ? 1
              : 0,
          onDestinationSelected: (index) =>
              context.go(['/', '/search', '/profile'][index]),
          destinations: const [
            NavigationDestination(
              icon: Icon(Icons.home_outlined),
              selectedIcon: Icon(Icons.home_rounded),
              label: 'Discover',
            ),
            NavigationDestination(icon: Icon(Icons.search), label: 'Explore'),
            NavigationDestination(
              icon: Icon(Icons.person_outline),
              selectedIcon: Icon(Icons.person),
              label: 'You',
            ),
          ],
        ),
      ),
      routes: [
        GoRoute(path: '/', builder: (context, state) => const HomeScreen()),
        GoRoute(
          path: '/search',
          builder: (context, state) => SearchScreen(
            key: ValueKey(state.uri.toString()),
            initialCategory: state.uri.queryParameters['category'],
            affordable: state.uri.queryParameters['affordable'] == 'true',
          ),
        ),
        GoRoute(
          path: '/profile',
          builder: (context, state) => const ProfileScreen(),
        ),
      ],
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
  late final router = createRouter();
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
  );
}
