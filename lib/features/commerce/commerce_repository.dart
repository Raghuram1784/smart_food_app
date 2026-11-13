import 'dart:convert';
import 'dart:math';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import '../auth/auth_provider.dart';
import '../auth/auth_repository.dart';

typedef Json = Map<String, dynamic>;
String checkoutKey() {
  final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
  bytes[6] = (bytes[6] & 15) | 64;
  bytes[8] = (bytes[8] & 63) | 128;
  final s = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
  return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}-${s.substring(16, 20)}-${s.substring(20)}';
}

abstract class CommerceRepository {
  Future<dynamic> request(String method, String path, [Json? data]);
  Future<Json?> pending(String userId);
  Future<Json> place(String userId, Json input);
  Future<void> forgetPending(String userId);
}

class ApiCommerceRepository implements CommerceRepository {
  final Dio dio;
  final FlutterSecureStorage storage;
  ApiCommerceRepository(
    this.dio, [
    this.storage = const FlutterSecureStorage(),
  ]);
  @override
  Future<dynamic> request(String method, String path, [Json? data]) async {
    final base = dio.options.baseUrl.replaceFirst(RegExp(r'/+$'), '');
    return (await dio.request(
      '$base/$path',
      data: data,
      options: Options(method: method),
    )).data['data'];
  }

  String key(String userId) => 'pending_checkout_$userId';
  @override
  Future<Json?> pending(String userId) async {
    final value = await storage.read(key: key(userId));
    return value == null ? null : Json.from(jsonDecode(value));
  }

  @override
  Future<void> forgetPending(String userId) => storage.delete(key: key(userId));
  @override
  Future<Json> place(String userId, Json input) async {
    await storage.write(key: key(userId), value: jsonEncode(input));
    final result = Json.from(await request('POST', 'orders', input));
    await forgetPending(userId);
    return result;
  }
}

final commerceRepositoryProvider = Provider<CommerceRepository>(
  (ref) => ApiCommerceRepository(ref.watch(authenticatedClientProvider)),
);
final customerIdProvider = Provider<String?>((ref) {
  final s = ref.watch(authProvider).asData?.value;
  return s != null && s.user.roles.contains('CUSTOMER') ? s.user.id : null;
});
final cartProvider = FutureProvider.autoDispose<Json?>((ref) {
  if (ref.watch(customerIdProvider) == null) return null;
  return ref
      .watch(commerceRepositoryProvider)
      .request('GET', 'cart')
      .then((v) => Json.from(v));
});
final addressesProvider = FutureProvider.autoDispose<List<Json>>((ref) async {
  if (ref.watch(customerIdProvider) == null) return [];
  return (await ref
              .watch(commerceRepositoryProvider)
              .request('GET', 'addresses')
          as List)
      .map((e) => Json.from(e))
      .toList();
});
final pendingCheckoutProvider = FutureProvider.autoDispose<Json?>((ref) {
  final id = ref.watch(customerIdProvider);
  return id == null ? null : ref.watch(commerceRepositoryProvider).pending(id);
});
final commerceReadProvider = FutureProvider.autoDispose.family<dynamic, String>(
  (ref, path) {
    final session = ref.watch(authProvider).asData?.value;
    if (session == null) throw StateError('Sign in required');
    return ref.watch(commerceRepositoryProvider).request('GET', path);
  },
);
String commerceError(Object error) {
  if (error is DioException) {
    if (error.response?.statusCode == 401) {
      return 'Your session ended. Please sign in again.';
    }
    final data = error.response?.data;
    if (data is Map) {
      final message = data['error']?['message'];
      if (message is String) {
        return message;
      }
      if (message is List) {
        return message.join('\n');
      }
    }
  }
  return 'Could not complete this request. Check your connection and retry.';
}
