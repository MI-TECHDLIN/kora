import 'dart:math';
import 'package:flutter/material.dart';
import '../theme/tokens.dart';

/// Dark canvas with slow-drifting violet glows behind every screen.
///
/// Glows are radial fades to transparent rather than blurred circles, so no
/// blur filter re-runs per frame; the glow layer sits in its own repaint
/// boundary so the drift never repaints the screen above it.
class GradientOrbBackground extends StatefulWidget {
  const GradientOrbBackground({super.key, this.child});
  final Widget? child;

  @override
  State<GradientOrbBackground> createState() => _GradientOrbBackgroundState();
}

class _GradientOrbBackgroundState extends State<GradientOrbBackground>
    with SingleTickerProviderStateMixin {
  // One slow controller; each glow drifts on its own phase of it.
  late final AnimationController _drift = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 24),
  );

  static const _glows = [
    // (colour, peak alpha, diameter, alignment, drift phase)
    (
      color: KoraColors.primary,
      alpha: 0.26,
      size: 420.0,
      at: Alignment(-1.1, -1.0),
      phase: 0.0,
    ),
    (
      color: KoraColors.primaryDark,
      alpha: 0.45,
      size: 380.0,
      at: Alignment(1.2, -0.35),
      phase: 0.25,
    ),
    (
      color: KoraColors.pink,
      alpha: 0.08,
      size: 300.0,
      at: Alignment(-1.1, 0.75),
      phase: 0.5,
    ),
    (
      color: KoraColors.blue,
      alpha: 0.07,
      size: 280.0,
      at: Alignment(1.0, 1.1),
      phase: 0.75,
    ),
  ];

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _drift.stop();
    } else if (!_drift.isAnimating) {
      _drift.repeat();
    }
  }

  @override
  void dispose() {
    _drift.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: KoraColors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _drift,
              builder: (context, _) => Stack(
                fit: StackFit.expand,
                children: [for (final g in _glows) _glow(g)],
              ),
            ),
          ),
          if (widget.child != null) RepaintBoundary(child: widget.child),
        ],
      ),
    );
  }

  Widget _glow(
    ({Color color, double alpha, double size, Alignment at, double phase}) g,
  ) {
    final t = (_drift.value + g.phase) * 2 * pi;
    return Align(
      alignment: g.at + Alignment(cos(t) * 0.08, sin(t) * 0.06),
      child: Container(
        width: g.size,
        height: g.size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              g.color.withValues(alpha: g.alpha),
              g.color.withValues(alpha: 0),
            ],
          ),
        ),
      ),
    );
  }
}
