import 'package:flutter/material.dart';

import '../../../core/theme/tokens.dart';

/// Slow, visible breath around a resting co-rider: warm and unhurried, for
/// the onboarding Hook. Wraps the orb rather than living inside
/// `MascotDisplay`, so the Rive swap-in stays a one-widget change. Holds
/// still when the platform asks to reduce motion.
class Breathing extends StatefulWidget {
  const Breathing({super.key, required this.child});

  final Widget child;

  @override
  State<Breathing> createState() => _BreathingState();
}

class _BreathingState extends State<Breathing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _breath = AnimationController(
    vsync: this,
    duration: VoiceOpsMotion.breath,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.95,
    end: 1.04,
  ).animate(CurvedAnimation(parent: _breath, curve: Curves.easeInOutSine));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      _breath
        ..stop()
        ..value = 0.5;
    } else if (!_breath.isAnimating) {
      _breath.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      ScaleTransition(scale: _scale, child: widget.child);
}
