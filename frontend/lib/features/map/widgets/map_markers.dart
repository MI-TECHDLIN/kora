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
    final size = active ? KoraMap.stopPinActive : KoraMap.stopPin;
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: KoraMotion.base,
          curve: KoraMotion.standard,
          width: size,
          height: size,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: active ? KoraColors.primary : KoraColors.elevated,
            border: Border.all(
              color: active
                  ? KoraColors.primaryLight
                  : KoraColors.primary,
              width: KoraGlass.borderWidth * 2,
            ),
            boxShadow: const [
              BoxShadow(
                color: KoraColors.primaryGlow,
                blurRadius: 12,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: label.isEmpty
              ? Icon(
                  TablerIcons.package,
                  size: KoraSize.iconSm,
                  color: KoraColors.onPrimary,
                )
              : Text(
                  label,
                  style: KoraText.label.copyWith(
                    color: KoraColors.onPrimary,
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
        width: KoraMap.positionHalo,
        height: KoraMap.positionHalo,
        alignment: Alignment.center,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: KoraColors.primaryTint,
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: KoraMap.positionDot + KoraSpacing.sm,
              height: KoraMap.positionDot + KoraSpacing.sm,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: KoraColors.primary,
                border: Border.all(
                  color: KoraColors.onPrimary,
                  width: KoraGlass.borderWidth * 2,
                ),
              ),
              child: Icon(
                vehicleMode.icon,
                size: KoraSize.iconSm,
                color: KoraColors.onPrimary,
              ),
            ),
            if (heading != null)
              Transform.rotate(
                key: const Key('vehicle-heading'),
                angle: heading * math.pi / 180,
                child: const SizedBox.square(
                  dimension: KoraMap.headingRing,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Icon(
                      TablerIcons.navigationFilled,
                      size: KoraMap.headingArrow,
                      color: KoraColors.onPrimary,
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
