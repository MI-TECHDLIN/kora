import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Main call-to-action: violet gradient, pill radius. Disabled when
/// [onPressed] is null.
class PrimaryButton extends StatelessWidget {
  const PrimaryButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.icon,
    this.expand = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  /// Stretch to the available width instead of hugging the label.
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final radius = BorderRadius.circular(VoiceOpsRadius.pill);

    return Semantics(
      button: true,
      enabled: enabled,
      child: AnimatedOpacity(
        duration: VoiceOpsMotion.fast,
        opacity: enabled ? 1 : 0.4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [VoiceOpsColors.primary, VoiceOpsColors.primaryDark],
            ),
            boxShadow: enabled
                ? const [
                    BoxShadow(
                      color: VoiceOpsColors.primaryGlow,
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
                  minHeight: VoiceOpsSize.control,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: VoiceOpsSpacing.xl,
                  ),
                  child: Row(
                    mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (icon != null) ...[
                        Icon(
                          icon,
                          size: VoiceOpsSize.iconMd,
                          color: VoiceOpsColors.onPrimary,
                        ),
                        const SizedBox(width: VoiceOpsSpacing.sm),
                      ],
                      Text(
                        label,
                        style: VoiceOpsText.title.copyWith(
                          color: VoiceOpsColors.onPrimary,
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
