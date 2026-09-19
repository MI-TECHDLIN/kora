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
            KoraSpacing.gutter,
            KoraSpacing.sm,
            KoraSpacing.gutter,
            KoraSpacing.xl,
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
                    size: KoraSize.iconLg,
                    color: KoraColors.textPrimary,
                  ),
                ),
              ),
              const SizedBox(height: KoraSpacing.lg),
              Semantics(
                header: true,
                child: Text(title, style: KoraText.headline),
              ),
              const SizedBox(height: KoraSpacing.sm),
              Text(subtitle, style: KoraText.bodyMuted),
              const SizedBox(height: KoraSpacing.xl),
              ...children,
            ],
          ),
        ),
      ),
    );
  }
}
