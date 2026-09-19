import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// [PrimaryButton] fills: the violet gradient everywhere, or solid white
/// with dark ink for the onboarding splash's editorial CTA.
enum PrimaryButtonTone { violet, white }

/// Main call-to-action: violet gradient (or white), pill radius. Disabled
/// when [onPressed] is null.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.trailingIcon,
    this.expand = false,
    this.tone = PrimaryButtonTone.violet,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Shown after the label, e.g. a forward arrow.
  final IconData? trailingIcon;

  /// Stretch to the available width instead of hugging the label.
  final bool expand;

  final PrimaryButtonTone tone;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(KoraRadius.pill);
    final white = tone == PrimaryButtonTone.white;
    final ink = white ? KoraMood.ink : KoraColors.onPrimary;

    Widget iconOf(IconData data) =>
        Icon(data, size: KoraSize.iconMd, color: ink);
    final text = Text(
      label,
      style: KoraText.title.copyWith(color: ink),
      overflow: TextOverflow.ellipsis,
    );

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        duration: KoraMotion.fast,
        opacity: enabled ? 1 : 0.4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            color: white ? KoraMood.paper : null,
            gradient: white
                ? null
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      KoraColors.primary,
                      KoraColors.primaryDark,
                    ],
                  ),
            boxShadow: enabled && !white
                ? const [
                    BoxShadow(
                      color: KoraColors.primaryGlow,
                      blurRadius: 20,
                      offset: Offset(0, 6),
                    ),
                  ]
                : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              onTap: onPressed,
              borderRadius: radius,
              child: ConstrainedBox(
                constraints: const BoxConstraints(
                  minHeight: KoraSize.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: KoraSpacing.xl,
                  ),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        iconOf(icon!),
                        const SizedBox(width: KoraSpacing.sm),
                      ],
                      // An expanded button always has a bounded width, so
                      // its label can ellipsize instead of overflowing.
                      if (expand) Flexible(child: text) else text,
                      if (trailingIcon != null) ...[
                        const SizedBox(width: KoraSpacing.sm),
                        iconOf(trailingIcon!),
                      ],
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
