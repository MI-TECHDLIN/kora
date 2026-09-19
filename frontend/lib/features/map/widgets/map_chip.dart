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
    this.tone = KoraColors.primaryLight,
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
      borderRadius: KoraRadius.control,
      fill: KoraColors.raised.withValues(alpha: 0.88),
      padding: const EdgeInsets.symmetric(
        horizontal: KoraSpacing.md,
        vertical: KoraSpacing.sm,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: KoraSize.iconSm, color: tone),
          const SizedBox(width: KoraSpacing.sm),
          Flexible(child: Text(message, style: KoraText.label)),
          if (actionLabel != null) ...[
            const SizedBox(width: KoraSpacing.sm),
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: KoraColors.primaryLight,
                minimumSize: const Size(
                  KoraSize.touchTarget,
                  KoraSize.touchTarget,
                ),
              ),
              child: Text(
                actionLabel!,
                style: KoraText.label.copyWith(
                  color: KoraColors.primaryLight,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
