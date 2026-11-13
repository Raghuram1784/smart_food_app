import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_repository.dart';

final authProvider = AsyncNotifierProvider<AuthController, AuthSession?>(
  AuthController.new,
);

class AuthController extends AsyncNotifier<AuthSession?> {
  Timer? timer;
  int generation = 0;
  @override
  Future<AuthSession?> build() async {
    final repo = ref.watch(authRepositoryProvider);
    final subscription = repo.invalidations.listen((_) {
      generation++;
      timer?.cancel();
      state = const AsyncData(null);
    });
    ref.onDispose(() {
      subscription.cancel();
      timer?.cancel();
    });
    final current = ++generation;
    final result = await repo.restore();
    if (!ref.mounted || current != generation) return null;
    if (result != null) _schedule(result);
    return result;
  }

  void _schedule(AuthSession session) {
    timer?.cancel();
    final remaining = session.expiresAt.difference(DateTime.now());
    timer = Timer(remaining.isNegative ? Duration.zero : remaining, () async {
      state = const AsyncData(null);
      try {
        await ref.read(authRepositoryProvider).expire();
      } catch (_) {
        /* Server also enforces expiration. */
      }
    });
  }

  Future<void> login(String email, String password) async {
    // Finish secure-storage restoration before issuing a replacement session.
    try {
      await future;
    } catch (_) {
      /* An explicit login can recover restoration failure. */
    }
    if (!ref.mounted) return;
    final current = ++generation;
    final result = await ref
        .read(authRepositoryProvider)
        .login(email, password);
    if (!ref.mounted || current != generation) return;
    _schedule(result);
    state = AsyncData(result);
  }

  Future<void> logout({bool all = false}) async {
    await ref.read(authRepositoryProvider).logout(all: all);
    if (!ref.mounted) return;
    generation++;
    timer?.cancel();
    state = const AsyncData(null);
  }

  Future<void> updateName(String name) async {
    final current = generation;
    final result = await ref.read(authRepositoryProvider).updateName(name);
    if (!ref.mounted || current != generation) return;
    _schedule(result);
    state = AsyncData(result);
  }
}

final accountContextProvider = FutureProvider.autoDispose
    .family<Map<String, dynamic>, String>((ref, path) {
      final session = ref.watch(authProvider).asData?.value;
      if (session == null) throw StateError('Sign in required');
      return ref.watch(authRepositoryProvider).context(path);
    });
