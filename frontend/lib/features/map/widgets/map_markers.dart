import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/vehicle_mode_provider.dart';

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

/// The driver's live position: their selected vehicle in a soft halo, with a
/// compass arrow that also turns while the phone is stationary.
class PositionMarker extends StatelessWidget {
  const PositionMarker({
    super.key,
    this.heading,
    this.vehicleMode = VehicleMode.car,
  });

  /// Degrees clockwise from north, or null when no heading is available.
  final double? heading;
  final VehicleMode vehicleMode;

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
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
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
              child: Icon(
                vehicleMode.icon,
                size: VoiceOpsSize.iconSm,
                color: VoiceOpsColors.onPrimary,
              ),
            ),
            if (heading != null)
              Transform.rotate(
                key: const Key('vehicle-heading'),
                angle: heading * math.pi / 180,
                child: const SizedBox.square(
                  dimension: VoiceOpsMap.headingRing,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Icon(
                      TablerIcons.navigationFilled,
                      size: VoiceOpsMap.headingArrow,
                      color: VoiceOpsColors.onPrimary,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
