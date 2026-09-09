import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Floating gradient-orb background — matches the JSX prototype's
/// .orb / .o1-o4 / @keyframes drift.
class GradientOrbBackground extends StatefulWidget {
  const GradientOrbBackground({super.key, this.child});
  final Widget? child;

  @override
  State<GradientOrbBackground> createState() => _GradientOrbBackgroundState();
}

class _GradientOrbBackgroundState extends State<GradientOrbBackground>
    with TickerProviderStateMixin {
  late final List<AnimationController> _controllers;
  static const _durations = [9000, 7000, 11000, 8500];
  static const _reverse = [false, true, false, true];

  @override
  void initState() {
    super.initState();
    _controllers = List.generate(4, (i) {
      return AnimationController(
        vsync: this,
        duration: Duration(milliseconds: _durations[i]),
      )..repeat(reverse: true);
    });
  }

  @override
  void dispose() {
    for (final c in _controllers) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFFECE8F9),
            Color(0xFFDDE8F5),
            Color(0xFFEDE0F8),
            Color(0xFFF5E8F8),
            Color(0xFFEEE8FF),
          ],
        ),
      ),
      child: Stack(
        children: [
          _orb(0, VoiceOpsColors.orbViolet, 340, top: -110, left: -90),
          _orb(1, VoiceOpsColors.orbPink, 295, top: 15, right: -85),
          _orb(2, VoiceOpsColors.orbBlue, 235, bottom: 50, left: -65),
          _orb(3, VoiceOpsColors.orbLilac, 215, bottom: -55, right: 25),
          if (widget.child != null) widget.child!,
        ],
      ),
    );
  }

  Widget _orb(
    int i,
    Color color,
    double size, {
    double? top,
    double? left,
    double? right,
    double? bottom,
  }) {
    return Positioned(
      top: top,
      left: left,
      right: right,
      bottom: bottom,
      child: ImageFiltered(
        imageFilter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
        child: AnimatedBuilder(
          animation: _controllers[i],
          builder: (context, child) {
            final t = _controllers[i].value;
            final dy = sin(t * pi) * (_reverse[i] ? 14 : -28);
            final scale = 1 + sin(t * pi) * 0.07;
            return Transform.translate(
              offset: Offset(0, dy),
              child: Transform.scale(scale: scale, child: child),
            );
          },
          child: Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [color.withOpacity(0.7), color.withOpacity(0.28)],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
