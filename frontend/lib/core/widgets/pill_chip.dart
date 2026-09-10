import 'package:flutter/material.dart';
import '../theme/tokens.dart';
import 'glass_card.dart';

/// Icon + label chip in the pastel-tile style: the icon sits on a solid
/// pastel disc, the chip body is an unblurred glass tint of the same accent.
/// `filled` makes the whole tile pastel with dark ink, for a single hero
/// chip — secondary accents are for sparing use.
class PillChip extends StatelessWidget {
  const PillChip({
    super.key,
    required this.icon,
    required this.label,
    this.accent = VoiceOpsColors.primaryLight,
    this.filled = false,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final bool filled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    // Checked here, not in the constructor, so PillChip stays const-able
    // (Color's == isn't allowed in constant expressions).
    assert(
      accent != VoiceOpsColors.live,
      'live lime is reserved for the mic-hot state — pick another accent',
    );
    final ink = filled ? VoiceOpsColors.onAccent : VoiceOpsColors.textPrimary;

    return Semantics(
      button: onTap != null,
      label: label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minHeight: VoiceOpsSize.touchTarget,
          ),
          child: GlassCard(
            frosted: false,
            shadow: false,
            borderRadius: VoiceOpsRadius.pill,
            fill: filled ? accent : accent.withValues(alpha: 0.10),
            border: Border.all(
              color: accent.withValues(alpha: filled ? 0 : 0.22),
              width: VoiceOpsGlass.borderWidth,
            ),
            padding: const EdgeInsets.fromLTRB(
              VoiceOpsSpacing.sm,
              VoiceOpsSpacing.sm,
              VoiceOpsSpacing.lg,
              VoiceOpsSpacing.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: VoiceOpsSize.iconXl,
                  height: VoiceOpsSize.iconXl,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: filled
                        ? VoiceOpsColors.onAccent.withValues(alpha: 0.12)
                        : accent,
                  ),
                  child: Icon(
                    icon,
                    size: VoiceOpsSize.iconSm,
                    color: VoiceOpsColors.onAccent,
                  ),
                ),
                const SizedBox(width: VoiceOpsSpacing.sm),
                Flexible(
                  child: Text(
                    label,
                    style: VoiceOpsText.label.copyWith(color: ink),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
