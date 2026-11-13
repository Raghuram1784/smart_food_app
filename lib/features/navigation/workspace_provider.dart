import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';

enum RoleWorkspace { customer, restaurantOwner, deliveryPartner, admin }

class ActiveWorkspaceNotifier extends Notifier<RoleWorkspace> {
  @override
  RoleWorkspace build() {
    final session = ref.watch(authProvider).asData?.value;
    return _defaultWorkspaceFor(session?.user);
  }

  static RoleWorkspace _defaultWorkspaceFor(AuthUser? user) {
    if (user == null) return RoleWorkspace.customer;
    final roles = user.roles;
    if (roles.contains('ADMIN')) return RoleWorkspace.admin;
    if (roles.contains('RESTAURANT_OWNER') && !roles.contains('CUSTOMER')) {
      return RoleWorkspace.restaurantOwner;
    }
    if (roles.contains('DELIVERY_PARTNER') && !roles.contains('CUSTOMER')) {
      return RoleWorkspace.deliveryPartner;
    }
    if (roles.contains('RESTAURANT_OWNER')) {
      return RoleWorkspace.restaurantOwner;
    }
    if (roles.contains('DELIVERY_PARTNER')) {
      return RoleWorkspace.deliveryPartner;
    }
    return RoleWorkspace.customer;
  }

  void setWorkspace(RoleWorkspace workspace) {
    state = workspace;
  }

  void resetToDefault() {
    final session = ref.read(authProvider).asData?.value;
    state = _defaultWorkspaceFor(session?.user);
  }
}

final activeWorkspaceProvider =
    NotifierProvider<ActiveWorkspaceNotifier, RoleWorkspace>(
      ActiveWorkspaceNotifier.new,
    );

String homeRouteForWorkspace(RoleWorkspace workspace, AuthUser? user) {
  switch (workspace) {
    case RoleWorkspace.restaurantOwner:
      return '/owner';
    case RoleWorkspace.deliveryPartner:
      return '/deliveries';
    case RoleWorkspace.admin:
      return '/dispatch';
    case RoleWorkspace.customer:
      return '/';
  }
}

String routeForRole(String role, AuthUser? user) {
  switch (role) {
    case 'RESTAURANT_OWNER':
      return '/owner';
    case 'DELIVERY_PARTNER':
      return '/deliveries';
    case 'ADMIN':
      return '/dispatch';
    case 'CUSTOMER':
    default:
      return '/';
  }
}
