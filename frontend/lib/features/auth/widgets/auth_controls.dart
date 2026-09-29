import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';

/// "Already have an account? Sign in" — the whole line is the tap target.
class AuthSwitchLink extends StatelessWidget {
  const AuthSwitchLink({
    super.key,
    required this.prompt,
    required this.action,
    required this.onPressed,
  });

  final String prompt;
  final String action;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          minimumSize: const Size(0, KoraSize.touchTarget),
          foregroundColor: KoraColors.primaryLight,
          shape: const StadiumBorder(),
        ),
        child: Text.rich(
          TextSpan(
            text: '$prompt ',
            style: KoraText.bodyMuted,
            children: [
              TextSpan(
                text: action,
                style: KoraText.weight(
                  KoraText.body,
                  FontWeight.w700,
                ).copyWith(color: KoraColors.primaryLight),
              ),
            ],
          ),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// An auth failure, read out by screen readers as it appears.
class AuthErrorBanner extends StatelessWidget {
  const AuthErrorBanner({super.key, required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      liveRegion: true,
      child: GlassCard(
        frosted: false,
        shadow: false,
        borderRadius: KoraRadius.control,
        fill: KoraColors.danger.withValues(alpha: 0.10),
        border: Border.all(
          color: KoraColors.danger.withValues(alpha: 0.35),
          width: KoraGlass.borderWidth,
        ),
        padding: const EdgeInsets.all(KoraSpacing.md),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              TablerIcons.alertCircle,
              size: KoraSize.iconMd,
              color: KoraColors.danger,
            ),
            const SizedBox(width: KoraSpacing.sm),
            Expanded(child: Text(message, style: KoraText.body)),
          ],
        ),
      ),
    );
  }
}

/// A dark notice bar in the app's palette, for messages that must outlive a
/// tap or a screen change.
SnackBar authNotice(String message) => SnackBar(
  behavior: SnackBarBehavior.floating,
  duration: KoraMotion.notice,
  backgroundColor: KoraColors.overlay,
  showCloseIcon: true,
  closeIconColor: KoraColors.textMuted,
  content: Text(message, style: KoraText.body),
);
