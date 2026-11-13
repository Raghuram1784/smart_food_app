import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../navigation/workspace_provider.dart';
import 'auth_provider.dart';
import 'auth_repository.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});
  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final email = TextEditingController(), password = TextEditingController();
  final form = GlobalKey<FormState>();
  bool hidden = true, busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    super.dispose();
  }

  Future<void> submit() async {
    if (busy || !form.currentState!.validate()) return;
    FocusManager.instance.primaryFocus?.unfocus();
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await ref.read(authProvider.notifier).login(email.text, password.text);
      password.clear();
      if (mounted) {
        final session = ref.read(authProvider).asData?.value;
        final user = session?.user;
        ref.read(activeWorkspaceProvider.notifier).resetToDefault();

        final returnParam = GoRouterState.of(context)
            .uri
            .queryParameters['return'];
        if (returnParam == 'back' && context.canPop()) {
          context.pop();
        } else {
          final workspace = ref.read(activeWorkspaceProvider);
          final destination = homeRouteForWorkspace(workspace, user);
          context.go(destination);
        }
      }
    } catch (e) {
      if (mounted) setState(() => error = authError(e));
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Your account')),
    body: SafeArea(
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 520),
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Form(
                key: form,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.restaurant_menu_rounded,
                      size: 40,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                    const SizedBox(height: 20),
                    Text(
                      'A familiar\nplace to return.',
                      style: Theme.of(context).textTheme.headlineLarge,
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Sign in to your account. Food discovery stays open to everyone.',
                    ),
                    const SizedBox(height: 28),
                    TextFormField(
                      key: const ValueKey('login-email'),
                      controller: email,
                      enabled: !busy,
                      keyboardType: TextInputType.emailAddress,
                      autofillHints: const [AutofillHints.username],
                      textInputAction: TextInputAction.next,
                      decoration: const InputDecoration(labelText: 'Email'),
                      validator: (v) =>
                          v == null ||
                              !RegExp(r'^[^\s@]+@[^\s@]+\.[^\s@]+$')
                                  .hasMatch(v.trim())
                          ? 'Enter a valid email address.'
                          : null,
                    ),
                    const SizedBox(height: 16),
                    TextFormField(
                      key: const ValueKey('login-password'),
                      controller: password,
                      enabled: !busy,
                      obscureText: hidden,
                      enableSuggestions: false,
                      autocorrect: false,
                      autofillHints: const [AutofillHints.password],
                      onFieldSubmitted: (_) => submit(),
                      decoration: InputDecoration(
                        labelText: 'Password',
                        suffixIcon: IconButton(
                          tooltip: hidden ? 'Show password' : 'Hide password',
                          onPressed: () => setState(() => hidden = !hidden),
                          icon: Icon(
                            hidden
                                ? Icons.visibility_outlined
                                : Icons.visibility_off_outlined,
                          ),
                        ),
                      ),
                      validator: (v) => v == null || v.isEmpty
                          ? 'Enter your password.'
                          : null,
                    ),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 16),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            error!,
                            style: TextStyle(
                              color: Theme.of(context).colorScheme.error,
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: busy ? null : submit,
                        child: busy
                            ? const SizedBox(
                                height: 22,
                                width: 22,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : const Text('Sign in'),
                      ),
                    ),
                    if (kDebugMode) ...[
                      const SizedBox(height: 24),
                      const Text('Development accounts'),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          for (final item in const {
                            'Customer': 'customer@demo.test',
                            'Restaurant (Deccan)': 'restaurant@demo.test',
                            'Chaat Mandi Owner': 'chaat.owner@demo.test',
                            'Delivery partner': 'rider@demo.test',
                            'Administrator': 'admin@demo.test',
                          }.entries)
                            ActionChip(
                              label: Text(item.key),
                              onPressed: busy
                                  ? null
                                  : () {
                                      email.text = item.value;
                                      password.clear();
                                    },
                            ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Email shortcuts only. Use the locally configured demo password.',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                    Center(
                      child: TextButton(
                        onPressed: () => context.go('/'),
                        child: const Text('Continue exploring'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
