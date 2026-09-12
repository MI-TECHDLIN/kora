import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';

/// A status line floating over the map (location off, tiles failed), with
/// an optional action that fixes it.
class MapChip extends StatelessWidget {
  const MapChip({
    super.key,
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
    this.tone = VoiceOpsColors.primaryLight,
  });

  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  /// Icon colour: violet for progress, amber for a problem.
  final Color tone;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      borderRadius: VoiceOpsRadius.control,
      fill: VoiceOpsColors.raised.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(
        horizontal: VoiceOpsSpacing.md,
        vertical: VoiceOpsSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: VoiceOpsSize.iconSm, color: tone),
          const SizedBox(width: VoiceOpsSpacing.sm),
          Flexible(child: Text(message, style: VoiceOpsText.label)),
          if (actionLabel != null) ...[
            const SizedBox(width: VoiceOpsSpacing.sm),
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onAction,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    minHeight: VoiceOpsSize.touchTarget,
                  ),
                  child: Center(
                    child: Text(
                      actionLabel!,
                      style: VoiceOpsText.label.copyWith(
                        color: VoiceOpsColors.primaryLight,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
