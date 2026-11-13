import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../../core/providers.dart';

class AuthUser {
  final String id, email, name;
  final List<String> roles;
  final List<({String id, String name})> restaurants;
  AuthUser.fromJson(Map<String, dynamic> j)
    : id = j['id'],
      email = j['email'],
      name = j['displayName'],
      roles = (j['roles'] as List).map((r) => r['roleName'] as String).toList(),
      restaurants = (j['memberships'] as List)
          .map(
            (m) => (
              id: m['restaurantId'] as String,
              name: m['restaurant']['name'] as String,
            ),
          )
          .toList();
}

class AuthSession {
  final AuthUser user;
  final DateTime expiresAt;
  AuthSession.fromJson(Map<String, dynamic> j)
    : user = AuthUser.fromJson(j['user']),
      expiresAt = DateTime.parse(j['session']['expiresAt']);
}

abstract class TokenStorage {
  Future<String?> read();
  Future<void> write(String value);
  Future<void> delete();
}

class SecureTokenStorage implements TokenStorage {
  final FlutterSecureStorage storage;
  SecureTokenStorage([this.storage = const FlutterSecureStorage()]);
  static const key = 'food_delivery_session_v1';
  @override
  Future<String?> read() => storage.read(key: key);
  @override
  Future<void> write(String value) => storage.write(key: key, value: value);
  @override
  Future<void> delete() => storage.delete(key: key);
}

class SessionVault {
  final TokenStorage storage;
  String? token;
  final changes = StreamController<void>.broadcast(sync: true);
  SessionVault(this.storage);
  Future<void> load() async {
    token = await storage.read();
  }

  Future<void> save(String value) async {
    await storage.write(value);
    token = value;
  }

  Future<void> clear() async {
    token = null;
    changes.add(null);
    await storage.delete();
  }

  Future<void> reject(String? rejected) async {
    if (rejected != null && rejected == token) {
      await clear();
    }
  }
}

abstract class AuthRepository {
  Stream<void> get invalidations;
  Future<AuthSession?> restore();
  Future<AuthSession> login(String email, String password);
  Future<void> logout({bool all = false});
  Future<void> expire();
  Future<AuthSession> updateName(String name);
  Future<Map<String, dynamic>> context(String path);
}

class ApiAuthRepository implements AuthRepository {
  final Dio dio;
  final SessionVault vault;
  ApiAuthRepository(this.dio, this.vault);
  String get base => dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
  @override
  Stream<void> get invalidations => vault.changes.stream;
  @override
  Future<AuthSession?> restore() async {
    await vault.load();
    if (vault.token == null) return null;
    try {
      return AuthSession.fromJson(
        (await dio.get('$base/auth/me')).data['data'],
      );
    } on DioException catch (e) {
      if (e.response?.statusCode == 401) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<AuthSession> login(String email, String password) async {
    final data = (await dio.post(
      '$base/auth/login',
      data: {'email': email.trim(), 'password': password},
    )).data['data'];
    final token = data['session']['token'] as String;
    try {
      await vault.save(token);
    } catch (_) {
      // A failed secure-storage write must not leave a usable client session behind.
      try {
        await dio.post(
          '$base/auth/logout',
          options: Options(headers: {'Authorization': 'Bearer $token'}),
        );
      } catch (_) {
        /* Server expiry remains bounded. */
      }
      rethrow;
    }
    return AuthSession.fromJson(data);
  }

  @override
  Future<void> logout({bool all = false}) async {
    try {
      await dio.post('$base/auth/${all ? 'logout-all' : 'logout'}');
    } on DioException catch (e) {
      if (e.response?.statusCode != 401) rethrow;
    }
    await vault.clear();
  }

  @override
  Future<void> expire() => vault.clear();
  @override
  Future<AuthSession> updateName(String name) async => AuthSession.fromJson(
    (await dio.patch(
      '$base/auth/me',
      data: {'displayName': name.trim()},
    )).data['data'],
  );
  @override
  Future<Map<String, dynamic>> context(String path) async =>
      Map<String, dynamic>.from(
        (await dio.get('$base/account/$path')).data['data'],
      );
}

final tokenStorageProvider = Provider<TokenStorage>(
  (ref) => SecureTokenStorage(),
);
final sessionVaultProvider = Provider((ref) {
  final vault = SessionVault(ref.watch(tokenStorageProvider));
  ref.onDispose(() => vault.changes.close());
  return vault;
});
final authenticatedClientProvider = Provider<Dio>((ref) {
  final public = ref.watch(apiClientProvider),
      vault = ref.watch(sessionVaultProvider);
  final dio = Dio(
    BaseOptions(
      baseUrl: public.options.baseUrl,
      followRedirects: false,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
    ),
  );
  final allowed = Uri.parse(dio.options.baseUrl);
  dio.interceptors.add(
    InterceptorsWrapper(
      onRequest: (options, handler) {
        // Never leak the token to a different host or an arbitrary absolute URL.
        if (options.uri.origin == allowed.origin &&
            !options.path.endsWith('/auth/login')) {
          if (vault.token != null) {
            options.headers.putIfAbsent(
              'Authorization',
              () => 'Bearer ${vault.token}',
            );
          }
        }
        handler.next(options);
      },
      onError: (error, handler) async {
        if (error.response?.statusCode == 401 &&
            !error.requestOptions.path.endsWith('/auth/login')) {
          final bearer =
              error.requestOptions.headers['Authorization'] as String?;
          try {
            await vault.reject(bearer?.replaceFirst('Bearer ', ''));
          } catch (_) {
            /* Session is cleared in memory; revoked tokens fail server-side. */
          }
        }
        handler.next(error);
      },
    ),
  );
  ref.onDispose(() => dio.close());
  return dio;
});
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => ApiAuthRepository(
    ref.watch(authenticatedClientProvider),
    ref.watch(sessionVaultProvider),
  ),
);

String authError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401) {
      return 'Email or password is incorrect.';
    }
    if (error.response?.statusCode == 403) {
      return 'This account does not have permission.';
    }
    if (error.response?.statusCode == 429) {
      return 'Too many sign-in attempts. Please try again later.';
    }
    return 'Could not reach your account. Check the connection and retry.';
  }
  return 'Could not securely access your session. Please retry.';
}
