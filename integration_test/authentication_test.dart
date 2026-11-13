import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:smart_food_demo/app.dart';
import 'package:smart_food_demo/core/providers.dart';
import 'package:smart_food_demo/features/auth/auth_provider.dart';
import 'package:smart_food_demo/features/auth/auth_repository.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  testWidgets(
    'live PostgreSQL login, secure restoration, roles and revocation',
    (tester) async {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('appearance', 'light');
      await SecureTokenStorage().delete();
      Future<void> launch() async {
        await tester.pumpWidget(
          ProviderScope(
            key: UniqueKey(),
            overrides: [preferencesProvider.overrideWithValue(prefs)],
            child: const FoodApp(),
          ),
        );
        await tester.pumpAndSettle();
      }

      Future<void> tap(Finder finder) async {
        await tester.ensureVisible(finder);
        await tester.tap(finder);
        await tester.pumpAndSettle();
      }

      Future<void> waitFor(Finder finder) async {
        for (var i = 0; i < 200; i++) {
          await tester.pump(const Duration(milliseconds: 100));
          if (finder.evaluate().isNotEmpty) {
            await tester.pumpAndSettle();
            return;
          }
        }
        expect(finder, findsWidgets);
      }

      final accounts = [
        (
          'customer@demo.test',
          const String.fromEnvironment('DEMO_CUSTOMER_PASSWORD'),
          'Customer account',
        ),
        (
          'restaurant@demo.test',
          const String.fromEnvironment('DEMO_RESTAURANT_PASSWORD'),
          'Your restaurant memberships',
        ),
        (
          'rider@demo.test',
          const String.fromEnvironment('DEMO_RIDER_PASSWORD'),
          'Your deliveries',
        ),
        (
          'admin@demo.test',
          const String.fromEnvironment('DEMO_ADMIN_PASSWORD'),
          'Delivery dispatch',
        ),
      ];
      await launch();
      await binding.convertFlutterSurfaceToImage();
      final dio = Dio(
        BaseOptions(baseUrl: const String.fromEnvironment('API_BASE_URL')),
      );
      for (var i = 0; i < accounts.length; i++) {
        final (email, password, label) = accounts[i];
        expect(
          password.isNotEmpty,
          true,
          reason: 'Private test credentials must be configured',
        );
        await tap(find.text('You'));
        await tap(find.text('Your account').first);
        await waitFor(find.byKey(const ValueKey('login-email')));
        if (i == 0) {
          await binding.takeScreenshot('01-login-light');
        }
        await tester.enterText(
          find.byKey(const ValueKey('login-email')),
          email,
        );
        await tester.enterText(
          find.byKey(const ValueKey('login-password')),
          password,
        );
        FocusManager.instance.primaryFocus?.unfocus();
        await tap(find.text('Sign in'));
        await waitFor(find.text(label));
        final scope = ProviderScope.containerOf(
          tester.element(find.byType(FoodApp)),
        );
        final token = scope.read(sessionVaultProvider).token!;
        expect(await SecureTokenStorage().read(), token);
        await binding.takeScreenshot('0${i + 2}-account');
        if (i == 1) {
          final response = await dio.get(
            'account/restaurant/other-kitchen',
            options: Options(
              headers: {'Authorization': 'Bearer $token'},
              validateStatus: (_) => true,
            ),
          );
          expect(response.statusCode, 403);
        }
        // Dispose every provider/router and restore from the native encrypted store.
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        await launch();
        await tap(find.text('You'));
        await waitFor(find.text(email));
        await tap(find.text(email));
        await waitFor(find.text(label));
        final restoredScope = ProviderScope.containerOf(
          tester.element(find.byType(FoodApp)),
        );
        expect(
          restoredScope.read(authProvider).requireValue?.user.email,
          email,
        );
        if (i == 3) {
          await restoredScope
              .read(appearanceProvider.notifier)
              .select(ThemeMode.dark);
          await tester.pumpAndSettle();
          await binding.takeScreenshot('06-admin-dark');
        }
        await tap(find.text('Sign out on all devices'));
        await waitFor(find.text('Make yourself\nat home.'));
        expect(await SecureTokenStorage().read(), isNull);
        final revoked = await dio.get(
          'auth/me',
          options: Options(
            headers: {'Authorization': 'Bearer $token'},
            validateStatus: (_) => true,
          ),
        );
        expect(revoked.statusCode, 401);
      }
      final public = await dio.get('catalog/search?q=dosa');
      expect(public.statusCode, 200);
      dio.close();
      await tester.pumpWidget(const SizedBox());
    },
  );
}
