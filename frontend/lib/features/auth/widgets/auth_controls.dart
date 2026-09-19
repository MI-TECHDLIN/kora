import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';

/// A hairline "Or" rule between the email form and Google sign-in.
class OrDivider extends StatelessWidget {
  const OrDivider({super.key});

  @override
  Widget build(BuildContext context) {
    const rule = Expanded(
      child: Divider(color: KoraColors.divider, height: 1),
    );
    return Row(
      children: [
        rule,
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: KoraSpacing.md),
          child: Text('Or', style: KoraText.bodyMuted),
        ),
        rule,
      ],
    );
  }
}

/// "Continue with Google": a full-width glass pill, secondary to the
/// violet [PrimaryButton] above it. Disabled when [onPressed] is null.
class GoogleButton extends StatelessWidget {
  const GoogleButton({super.key, required this.onPressed});

  static const label = 'Continue with Google';

  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      excludeSemantics: true,
      child: AnimatedOpacity(
        duration: KoraMotion.fast,
        opacity: enabled ? 1 : 0.4,
        child: GlassCard(
          frosted: false,
          shadow: false,
          borderRadius: KoraRadius.pill,
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              customBorder: const StadiumBorder(),
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: KoraSize.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoraSpacing.xl,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        TablerIcons.brandGoogle,
                        size: KoraSize.iconMd,
                        color: KoraColors.textPrimary,
                      ),
                      const SizedBox(width: KoraSpacing.sm),
                      Flexible(
                        child: Text(
                          label,
                          style: KoraText.title,
                          overflow: TextOverflow.ellipsis,
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
}

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
