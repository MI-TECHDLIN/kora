import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';

/// A numbered delivery stop. The stop being navigated to is larger and
/// filled violet; the rest are dark with a violet rim.
class StopPin extends StatelessWidget {
  const StopPin({
    super.key,
    required this.label,
    required this.active,
    required this.semanticLabel,
    this.onTap,
  });

  /// The stop's sequence number, or empty for an unnumbered stop.
  final String label;
  final bool active;
  final String semanticLabel;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final size = active ? VoiceOpsMap.stopPinActive : VoiceOpsMap.stopPin;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: VoiceOpsMotion.base,
          curve: VoiceOpsMotion.standard,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? VoiceOpsColors.primary : VoiceOpsColors.elevated,
            border: Border.all(
              color: active
                  ? VoiceOpsColors.primaryLight
                  : VoiceOpsColors.primary,
              width: VoiceOpsGlass.borderWidth * 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: VoiceOpsColors.primaryGlow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: label.isEmpty
              ? Icon(
                  TablerIcons.package,
                  size: VoiceOpsSize.iconSm,
                  color: VoiceOpsColors.onPrimary,
                )
              : Text(
                  label,
                  style: VoiceOpsText.label.copyWith(
                    color: VoiceOpsColors.onPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}

/// The driver's live position: a solid dot in a soft halo, or a heading
/// arrow while moving.
class PositionMarker extends StatelessWidget {
  const PositionMarker({super.key, this.heading});

  /// Degrees clockwise from north, or null when standing still.
  final double? heading;

  @override
  Widget build(BuildContext context) {
    final heading = this.heading;
    return Semantics(
      label: 'Your location',
      child: Container(
        width: VoiceOpsMap.positionHalo,
        height: VoiceOpsMap.positionHalo,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: VoiceOpsColors.primaryTint,
        ),
        child: Container(
          width: VoiceOpsMap.positionDot + VoiceOpsSpacing.sm,
          height: VoiceOpsMap.positionDot + VoiceOpsSpacing.sm,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: VoiceOpsColors.primary,
            border: Border.all(
              color: VoiceOpsColors.onPrimary,
              width: VoiceOpsGlass.borderWidth * 2,
            ),
          ),
          child: heading == null
              ? null
              : Transform.rotate(
                  angle: heading * math.pi / 180,
                  child: const Icon(
                    TablerIcons.navigationFilled,
                    size: VoiceOpsSize.iconSm,
                    color: VoiceOpsColors.onPrimary,
                  ),
                ),
        ),
      ),
    );
  }
}
