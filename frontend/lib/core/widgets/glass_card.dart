import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Reusable glassmorphism container — the phone frame, chips, task cards,
/// and input row all build on this. SDD v2.0 §12 Week 1.
class GlassCard extends StatelessWidget {
  const GlassCard({
    super.key,
    required this.child,
    this.borderRadius = VoiceOpsRadius.card,
    this.blur = 20,
    this.opacity = 0.62,
    this.padding,
    this.margin,
    this.border,
  });

  final Widget child;
  final double borderRadius;
  final double blur;
  final double opacity;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final Border? border;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(borderRadius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur),
          child: Container(
            padding: padding,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(opacity),
              borderRadius: BorderRadius.circular(borderRadius),
              border:
                  border ??
                  Border.all(color: VoiceOpsColors.glassBorder, width: 1),
              boxShadow: [
                BoxShadow(
                  color: VoiceOpsColors.primary.withOpacity(0.07),
                  blurRadius: 10,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}
