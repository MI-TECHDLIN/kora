import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Restrained glass container — nav bar, input row, cards and chips build
/// on this. The backdrop blur is capped at [VoiceOpsGlass.blur]; pass
/// `frosted: false` for repeated items (chip grids, list rows) where a
/// blur per item would cost frames on a mid-range Android.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = VoiceOpsRadius.card,
    this.frosted = true,
    this.fill = VoiceOpsGlass.fill,
    this.padding,
    this.margin,
    this.border,
    this.shadow = true,
  });

  final Widget child;
  final double borderRadius;
  final bool frosted;
  final Color fill;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final BoxBorder? border;
  final bool shadow;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);

    Widget surface = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border:
            border ??
            Border.all(
              color: VoiceOpsGlass.border,
              width: VoiceOpsGlass.borderWidth,
            ),
      ),
      child: Padding(padding: padding ?? EdgeInsets.zero, child: child),
    );

    if (frosted) {
      surface = ClipRRect(
        borderRadius: radius,
        child: BackdropFilter(
          filter: ImageFilter.blur(
            sigmaX: VoiceOpsGlass.blur,
            sigmaY: VoiceOpsGlass.blur,
          ),
          child: surface,
        ),
      );
    }

    // Shadow sits outside the clip so it is actually visible.
    return Container(
      margin: margin,
      decoration: shadow
          ? BoxDecoration(borderRadius: radius, boxShadow: VoiceOpsGlass.shadow)
          : null,
      child: surface,
    );
  }
}
