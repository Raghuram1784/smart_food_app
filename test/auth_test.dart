import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/account_screen.dart';
import 'package:smart_food_demo/features/auth/login_screen.dart';

AuthSession session([String role = 'CUSTOMER']) => AuthSession.fromJson({
  'user': {
    'id': 'user-1',
    'email': 'person@test.invalid',
    'displayName': 'Test Person',
    'roles': [
      {'roleName': role},
    ],
    'memberships': role == 'RESTAURANT_OWNER'
        ? [
            {
              'restaurantId': 'owned',
              'restaurant': {'name': 'Owned kitchen'},
            },
          ]
        : [],
  },
  'session': {
    'expiresAt': DateTime.now().add(const Duration(hours: 1)).toIso8601String(),
  },
});

class MemoryStorage implements TokenStorage {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String token) async {
    value = token;
  }

  @override
  Future<void> delete() async {
    value = null;
  }
}

class FakeAuth implements AuthRepository {
  final events = StreamController<void>.broadcast(sync: true);
  AuthSession? saved;
  Completer<AuthSession?>? restoration;
  Completer<AuthSession>? update;
  bool failLogout = false;
  int loginCalls = 0;
  @override
  Stream<void> get invalidations => events.stream;
  @override
  Future<AuthSession?> restore() => restoration?.future ?? Future.value(saved);
  @override
  Future<AuthSession> login(String email, String password) async {
    loginCalls++;
    return saved = session();
  }

  @override
  Future<void> logout({bool all = false}) async {
    if (failLogout) throw StateError('offline');
    saved = null;
    events.add(null);
  }

  @override
  Future<void> expire() async {
    saved = null;
    events.add(null);
  }

  @override
  Future<AuthSession> updateName(String name) =>
      update?.future ?? Future.value(saved!);
  @override
  Future<Map<String, dynamic>> context(String path) async =>
      path.startsWith('restaurant')
      ? {
          'restaurant': {'operatingStatus': 'OPEN'},
        }
      : {'notice': 'Operations coming later.'};
}

void main() {
  test(
    'secure vault clears only the rejected session, not a newer login',
    () async {
      final storage = MemoryStorage(), vault = SessionVault(MemoryStorage());
      final first = SessionVault(storage);
      await first.save('first');
      final restored = SessionVault(storage);
      await restored.load();
      expect(restored.token, 'first');
      await restored.save('new');
      await restored.reject('first');
      expect(restored.token, 'new');
      await restored.reject('new');
      expect(storage.value, isNull);
      expect(restored.token, isNull);
      await first.changes.close();
      await restored.changes.close();
      await vault.changes.close();
    },
  );
  test(
    'login waits for restoration and logout failure preserves the session',
    () async {
      final repo = FakeAuth()..restoration = Completer<AuthSession?>();
      final container = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
      );
      addTearDown(container.dispose);
      addTearDown(repo.events.close);
      final controller = container.read(authProvider.notifier);
      final login = controller.login('person@test.invalid', 'password');
      await Future<void>.delayed(Duration.zero);
      expect(repo.loginCalls, 0);
      repo.restoration!.complete(null);
      await login;
      expect(
        container.read(authProvider).requireValue?.user.name,
        'Test Person',
      );
      repo.failLogout = true;
      await expectLater(controller.logout(), throwsStateError);
      expect(container.read(authProvider).requireValue, isNotNull);
      repo.failLogout = false;
      await controller.logout(all: true);
      expect(container.read(authProvider).requireValue, isNull);
    },
  );
  test('late profile response cannot restore a revoked session', () async {
    final repo = FakeAuth()
      ..saved = session()
      ..update = Completer<AuthSession>();
    final container = ProviderContainer(
      overrides: [authRepositoryProvider.overrideWithValue(repo)],
    );
    addTearDown(container.dispose);
    addTearDown(repo.events.close);
    await container.read(authProvider.future);
    final pending = container.read(authProvider.notifier).updateName('Changed');
    repo.events.add(null);
    repo.update!.complete(session());
    await pending;
    expect(container.read(authProvider).requireValue, isNull);
  });
  for (final role in [
    'CUSTOMER',
    'RESTAURANT_OWNER',
    'DELIVERY_PARTNER',
    'ADMIN',
  ]) {
    testWidgets(
      '$role account uses verified context and hides after invalidation',
      (tester) async {
        final repo = FakeAuth()..saved = session(role);
        addTearDown(repo.events.close);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [authRepositoryProvider.overrideWithValue(repo)],
            child: const MaterialApp(home: AccountScreen()),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.text('Test Person'), findsOneWidget);
        if (role == 'RESTAURANT_OWNER') {
          expect(find.text('Owned kitchen'), findsOneWidget);
        }
        if (role == 'ADMIN') {
          expect(find.text('Delivery dispatch'), findsOneWidget);
        }
        repo.events.add(null);
        await tester.pumpAndSettle();
        expect(find.text('Test Person'), findsNothing);
        expect(find.text('Sign in to access your account.'), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      },
    );
  }
  testWidgets('login validates inputs and never submits empty credentials', (
    tester,
  ) async {
    final repo = FakeAuth();
    addTearDown(repo.events.close);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [authRepositoryProvider.overrideWithValue(repo)],
        child: const MaterialApp(home: LoginScreen()),
      ),
    );
    await tester.ensureVisible(find.text('Sign in'));
    await tester.tap(find.text('Sign in'));
    await tester.pumpAndSettle();
    expect(repo.loginCalls, 0);
    expect(find.text('Enter your password.'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
