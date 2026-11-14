import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/commerce/operations_screen.dart';
import 'package:smart_food_demo/features/navigation/role_shell.dart';
import 'package:smart_food_demo/features/navigation/workspace_provider.dart';

AuthSession _makeUserSession({
  required String email,
  required String role,
  List<String>? additionalRoles,
}) {
  final allRoles = [role, ...?additionalRoles];
  return AuthSession.fromJson({
    'user': {
      'id': 'u-$role',
      'email': email,
      'displayName': 'Test $role',
      'roles': [
        for (final r in allRoles) {'roleName': r},
      ],
      'memberships': role == 'RESTAURANT_OWNER'
          ? [
              {
                'restaurantId': 'chaat-mandi-kondapur',
                'restaurant': {'name': 'Chaat Mandi'},
              },
            ]
          : [],
    },
    'session': {
      'expiresAt': DateTime.now()
          .add(const Duration(hours: 2))
          .toIso8601String(),
    },
  });
}

class _StaticWorkspaceNotifier extends ActiveWorkspaceNotifier {
  final RoleWorkspace _initial;
  _StaticWorkspaceNotifier(this._initial);
  @override
  RoleWorkspace build() => _initial;
}

void main() {
  group('RBAC and Navigation Redirection', () {
    test('homeRouteForWorkspace returns correct path per role workspace', () {
      final customerSession = _makeUserSession(
        email: 'customer@demo.test',
        role: 'CUSTOMER',
      );
      final ownerSession = _makeUserSession(
        email: 'chaat.owner@demo.test',
        role: 'RESTAURANT_OWNER',
      );
      final riderSession = _makeUserSession(
        email: 'rider@demo.test',
        role: 'DELIVERY_PARTNER',
      );
      final adminSession = _makeUserSession(
        email: 'admin@demo.test',
        role: 'ADMIN',
      );

      expect(
        homeRouteForWorkspace(RoleWorkspace.customer, customerSession.user),
        '/',
      );
      expect(
        homeRouteForWorkspace(RoleWorkspace.restaurantOwner, ownerSession.user),
        '/owner',
      );
      expect(
        homeRouteForWorkspace(RoleWorkspace.deliveryPartner, riderSession.user),
        '/deliveries',
      );
      expect(
        homeRouteForWorkspace(RoleWorkspace.admin, adminSession.user),
        '/dispatch',
      );
    });

    test('routeForRole maps user role strings directly', () {
      expect(routeForRole('CUSTOMER', null), '/');
      expect(routeForRole('RESTAURANT_OWNER', null), '/owner');
      expect(routeForRole('DELIVERY_PARTNER', null), '/deliveries');
      expect(routeForRole('ADMIN', null), '/dispatch');
      expect(routeForRole('UNKNOWN', null), '/');
    });

    test('activeWorkspaceProvider switches correctly', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(activeWorkspaceProvider), RoleWorkspace.customer);

      container
          .read(activeWorkspaceProvider.notifier)
          .setWorkspace(RoleWorkspace.restaurantOwner);
      expect(
        container.read(activeWorkspaceProvider),
        RoleWorkspace.restaurantOwner,
      );

      container
          .read(activeWorkspaceProvider.notifier)
          .setWorkspace(RoleWorkspace.deliveryPartner);
      expect(
        container.read(activeWorkspaceProvider),
        RoleWorkspace.deliveryPartner,
      );

      container
          .read(activeWorkspaceProvider.notifier)
          .setWorkspace(RoleWorkspace.admin);
      expect(container.read(activeWorkspaceProvider), RoleWorkspace.admin);
    });
  });

  group('Customization Name Clarity', () {
    test('cleanItemPortion strips parenthetical piece count when variant is present', () {
      expect(
        cleanItemPortion(
          'Crisp Pani Puri Kit (8 pc)',
          'Family Party Kit (24 pc)',
        ),
        'Crisp Pani Puri Kit',
      );
      expect(
        cleanItemPortion('Steamed Idli (3 pc)', 'Party Pack (12 pc)'),
        'Steamed Idli',
      );
      expect(
        cleanItemPortion('Hyderabadi Chicken Biryani', null),
        'Hyderabadi Chicken Biryani',
      );
      expect(
        cleanItemPortion('Hyderabadi Chicken Biryani', ''),
        'Hyderabadi Chicken Biryani',
      );
    });
  });

  group('RoleShell UI Destinations', () {
    testWidgets('renders customer navigation bar with all 5 required tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceProvider.overrideWith(
              () => _StaticWorkspaceNotifier(RoleWorkspace.customer),
            ),
          ],
          child: const MaterialApp(
            home: RoleShell(
              child: Scaffold(body: Text('Customer Home Content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Discover'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Cart'), findsOneWidget);
      expect(find.text('My Orders'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets(
      'renders restaurant owner navigation bar with operational tabs',
      (tester) async {
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              activeWorkspaceProvider.overrideWith(
                () => _StaticWorkspaceNotifier(RoleWorkspace.restaurantOwner),
              ),
            ],
            child: const MaterialApp(
              home: RoleShell(
                child: Scaffold(body: Text('Owner Dashboard Content')),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('Dashboard'), findsOneWidget);
        expect(find.text('New Orders'), findsOneWidget);
        expect(find.text('Kitchen'), findsOneWidget);
        expect(find.text('History'), findsOneWidget);
        expect(find.text('Account'), findsOneWidget);
      },
    );

    testWidgets('renders delivery partner navigation bar with delivery tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceProvider.overrideWith(
              () => _StaticWorkspaceNotifier(RoleWorkspace.deliveryPartner),
            ),
          ],
          child: const MaterialApp(
            home: RoleShell(
              child: Scaffold(body: Text('Rider Dashboard Content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Assigned'), findsOneWidget);
      expect(find.text('In Transit'), findsOneWidget);
      expect(find.text('History'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });

    testWidgets('renders admin navigation bar with dispatch tabs', (
      tester,
    ) async {
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            activeWorkspaceProvider.overrideWith(
              () => _StaticWorkspaceNotifier(RoleWorkspace.admin),
            ),
          ],
          child: const MaterialApp(
            home: RoleShell(
              child: Scaffold(body: Text('Admin Dispatch Content')),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Dispatch'), findsOneWidget);
      expect(find.text('Unassigned'), findsOneWidget);
      expect(find.text('Riders'), findsOneWidget);
      expect(find.text('Account'), findsOneWidget);
    });
  });
}
