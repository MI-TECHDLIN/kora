import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../providers/voice_onboarding_provider.dart';
import '../data/auth_repository.dart';
import '../validation.dart';
import '../widgets/auth_attempt.dart';
import '../widgets/auth_controls.dart';
import '../widgets/auth_entrance.dart';
import '../widgets/auth_layout.dart';
import '../widgets/auth_text_field.dart';
import '../widgets/terms_agreement.dart';

/// Email sign-up: name, email, password and phone (drivers.phone is
/// required), gated on agreeing to the terms. Google is the alternative.
class SignUpScreen extends ConsumerStatefulWidget {
  const SignUpScreen({super.key});

  static const title = 'Create account';

  @override
  ConsumerState<SignUpScreen> createState() => _SignUpScreenState();
}

class _SignUpScreenState extends ConsumerState<SignUpScreen>
    with SingleTickerProviderStateMixin, AuthAttempt, AuthEntrance {
  @override
  int get entranceItemCount => 5;

  final _form = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _phone = TextEditingController();

  bool _agreed = false;
  bool _showTermsError = false;

  /// Set once the account exists but waits on email confirmation.
  String? _confirmationSentTo;

  @override
  void dispose() {
    for (final c in [_name, _email, _password, _phone]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _createAccount() async {
    final fieldsOk = _form.currentState!.validate();
    setState(() => _showTermsError = !_agreed);
    if (!fieldsOk || !_agreed) return;

    final email = _email.text.trim();
    final result = await attempt(
      (auth) => auth.signUp(
        SignUpDetails(
          fullName: _name.text.trim(),
          email: email,
          password: _password.text,
          phone: AuthValidators.normalizePhone(_phone.text),
        ),
      ),
    );
    if (result == SignUpResult.confirmEmail) {
      if (mounted) setState(() => _confirmationSentTo = email);
    } else if (result == SignUpResult.signedIn && mounted) {
      // The router's auth gate takes over from here. Flag the voice step so
      // its redirect can insert itself before the main app — but only on a
      // device that has never shown it, and never for a plain sign-in.
      await ref.read(voiceOnboardingProvider.notifier).showIfNeverShown();
    }
  }

  @override
  Widget build(BuildContext context) {
    final sentTo = _confirmationSentTo;
    if (sentTo != null) {
      return AuthLayout(
        title: 'Check your inbox',
        subtitle: 'One more step before your first shift.',
        children: [_ConfirmEmailCard(email: sentTo)],
      );
    }

    return AuthLayout(
      title: SignUpScreen.title,
      subtitle: 'Set up your driver account to meet your co-rider.',
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
                    label: 'Full name',
                    hint: 'Enter your name',
                    icon: TablerIcons.user,
                    controller: _name,
                    enabled: !busy,
                    validator: AuthValidators.fullName,
                    keyboardType: TextInputType.name,
                    textCapitalization: TextCapitalization.words,
                    autofillHints: const [AutofillHints.name],
                  ),
                ),
                const SizedBox(height: KoraSpacing.lg),
                arrive(
                  1,
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
                  2,
                  AuthTextField(
                    label: 'Password',
                    hint: 'Create a password',
                    icon: TablerIcons.lock,
                    controller: _password,
                    enabled: !busy,
                    obscure: true,
                    validator: AuthValidators.newPassword,
                    autofillHints: const [AutofillHints.newPassword],
                  ),
                ),
                const SizedBox(height: KoraSpacing.lg),
                arrive(
                  3,
                  AuthTextField(
                    label: 'Phone number',
                    hint: '+234 801 234 5678',
                    icon: TablerIcons.phone,
                    controller: _phone,
                    enabled: !busy,
                    validator: AuthValidators.phone,
                    keyboardType: TextInputType.phone,
                    textInputAction: TextInputAction.done,
                    autofillHints: const [AutofillHints.telephoneNumber],
                    onSubmitted: (_) => _createAccount(),
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KoraSpacing.md),
        TermsAgreement(
          value: _agreed,
          enabled: !busy,
          showError: _showTermsError && !_agreed,
          onChanged: (agreed) => setState(() => _agreed = agreed),
        ),
        const SizedBox(height: KoraSpacing.lg),
        if (error case final message?) ...[
          AuthErrorBanner(message: message),
          const SizedBox(height: KoraSpacing.lg),
        ],
        arrive(
          4,
          PrimaryButton(
            label: busy ? 'Creating account…' : SignUpScreen.title,
            expand: true,
            onPressed: busy ? null : _createAccount,
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
          prompt: 'Already have an account?',
          action: 'Sign in',
          onPressed: busy ? null : () => context.go(AppRoutes.signIn),
        ),
      ],
    );
  }
}

/// Shown when Supabase holds the session back until the email is confirmed.
class _ConfirmEmailCard extends StatelessWidget {
  const _ConfirmEmailCard({required this.email});

  final String email;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GlassCard(
          padding: const EdgeInsets.all(KoraSpacing.xl),
          child: Semantics(
            liveRegion: true,
            child: Column(
              children: [
                const Icon(
                  TablerIcons.mailOpened,
                  size: KoraSize.iconXl,
                  color: KoraColors.primaryLight,
                ),
                const SizedBox(height: KoraSpacing.md),
                Text(
                  'We sent a confirmation link to $email. Open it on this '
                  'phone, then sign in.',
                  style: KoraText.body,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: KoraSpacing.xl),
        PrimaryButton(
          label: 'Go to sign in',
          expand: true,
          onPressed: () => context.go(AppRoutes.signIn),
        ),
      ],
    );
  }
}
