import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/theme/tokens.dart';

/// Shared frame for the sign-up and sign-in forms: a back button to the
/// welcome screen, a headline and subtitle, then [children], scrolling over
/// the app's gradient background so the keyboard never covers a field.
class AuthLayout extends StatelessWidget {
  const AuthLayout({
    super.key,
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      body: SafeArea(
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            VoiceOpsSpacing.gutter,
            VoiceOpsSpacing.sm,
            VoiceOpsSpacing.gutter,
            VoiceOpsSpacing.xl,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: IconButton(
                  tooltip: 'Back',
                  onPressed: () => context.canPop()
                      ? context.pop()
                      : context.go(AppRoutes.welcome),
                  icon: const Icon(
                    TablerIcons.arrowLeft,
                    size: VoiceOpsSize.iconLg,
                    color: VoiceOpsColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: VoiceOpsSpacing.lg),
              Semantics(
                header: true,
                child: Text(title, style: VoiceOpsText.headline),
              ),
              const SizedBox(height: VoiceOpsSpacing.sm),
              Text(subtitle, style: VoiceOpsText.bodyMuted),
              const SizedBox(height: VoiceOpsSpacing.xl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
