import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../app/router.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../onboarding/widgets/fill_or_scroll.dart';
import '../widgets/auth_controls.dart';

/// The signed-out entry point, where onboarding hands off: the resting
/// co-rider, the VoiceOps promise, and the two ways in.
class WelcomeScreen extends StatelessWidget {
  const WelcomeScreen({super.key});

  static const headline = 'Welcome to VoiceOps';
  static const tagline =
      'Talk to your operations. Let your operations talk back.';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: KoraSpacing.gutter,
          ),
          child: FillOrScroll(
            builder: (context, viewport) => Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const SizedBox(height: KoraSpacing.lg),
                Text(
                  'VOICEOPS',
                  textAlign: TextAlign.center,
                  style: KoraText.caption.copyWith(
                    color: KoraColors.textPrimary,
                  ),
                ),
                Expanded(
                  child: Center(
                    child: MascotDisplay(
                      state: AgentState.idle,
                      size: math.min(
                        KoraSize.orbHero,
                        viewport.height * 0.26,
                      ),
                    ),
                  ),
                ),
                Semantics(
                  header: true,
                  child: Text(
                    headline,
                    style: FillOrScroll.headlineFor(viewport),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: KoraSpacing.md),
                Text(
                  tagline,
                  style: KoraText.bodyMuted,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: KoraSpacing.xxl),
                PrimaryButton(
                  label: 'Get started',
                  expand: true,
                  onPressed: () => context.go(AppRoutes.signUp),
                ),
                const SizedBox(height: KoraSpacing.sm),
                AuthSwitchLink(
                  prompt: 'Already have an account?',
                  action: 'Sign in',
                  onPressed: () => context.go(AppRoutes.signIn),
                ),
                const SizedBox(height: KoraSpacing.sm),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
