import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primary_button.dart';
import '../validation.dart';
import '../widgets/auth_attempt.dart';
import '../widgets/auth_controls.dart';
import '../widgets/auth_entrance.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_text_field.dart';

/// Email + password sign-in, with Google as the alternative.
class SignInScreen extends ConsumerStatefulWidget {
  const SignInScreen({super.key});

  static const title = 'Sign in';

  @override
  ConsumerState<SignInScreen> createState() => _SignInScreenState();
}

class _SignInScreenState extends ConsumerState<SignInScreen>
    with SingleTickerProviderStateMixin, AuthAttempt, AuthEntrance {
  @override
  int get entranceItemCount => 3;

  final _form = GlobalKey<FormState>();
  final _email = TextEditingController();
  final _password = TextEditingController();

  @override
  void dispose() {
    _email.dispose();
    _password.dispose();
    super.dispose();
  }

  Future<void> _signIn() async {
    if (!_form.currentState!.validate()) return;
    // Success needs nothing here: the router's auth gate takes over.
    await attempt(
      (auth) =>
          auth.signIn(email: _email.text.trim(), password: _password.text),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AuthLayout(
      title: 'Welcome back',
      subtitle: 'Sign in to pick up your shift where you left it.',
      children: [
        Form(
          key: _form,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                arrive(
                  0,
                  AuthTextField(
                    label: 'Email',
                    hint: 'Enter your email',
                    icon: TablerIcons.mail,
                    controller: _email,
                    enabled: !busy,
                    validator: AuthValidators.email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                  ),
                ),
                const SizedBox(height: KoraSpacing.lg),
                arrive(
                  1,
                  AuthTextField(
                    label: 'Password',
                    hint: 'Enter your password',
                    icon: TablerIcons.lock,
                    controller: _password,
                    enabled: !busy,
                    obscure: true,
                    validator: AuthValidators.password,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _signIn(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KoraSpacing.xl),
        if (error case final message?) ...[
          AuthErrorBanner(message: message),
          const SizedBox(height: KoraSpacing.lg),
        ],
        arrive(
          2,
          PrimaryButton(
            label: busy ? 'Signing in…' : SignInScreen.title,
            expand: true,
            onPressed: busy ? null : _signIn,
          ),
        ),
        const SizedBox(height: KoraSpacing.xl),
        const OrDivider(),
        const SizedBox(height: KoraSpacing.xl),
        GoogleButton(
          onPressed: busy ? null : () => attempt((a) => a.signInWithGoogle()),
        ),
        const SizedBox(height: KoraSpacing.md),
        AuthSwitchLink(
          prompt: "Don't have an account?",
          action: 'Sign up',
          onPressed: busy ? null : () => context.go(AppRoutes.signUp),
        ),
      ],
    );
  }
}
