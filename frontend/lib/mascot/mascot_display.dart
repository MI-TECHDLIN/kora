import 'package:flutter/material.dart';

import '../core/theme/tokens.dart';
import 'mascot_state.dart';

enum OrbMaterial { holographic, chrome }

class OrbMaterialScope extends InheritedWidget {
  const OrbMaterialScope({
    super.key,
    required this.material,
    required super.child,
  });

  final OrbMaterial material;

  static OrbMaterial of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<OrbMaterialScope>()
          ?.material ??
      OrbMaterial.chrome;

  @override
  bool updateShouldNotify(OrbMaterialScope oldWidget) =>
      material != oldWidget.material;
}

class MascotDisplay extends StatelessWidget {
  const MascotDisplay({
    super.key,
    required this.state,
    this.size = VoiceOpsSize.orbHero,
    this.material,
  });

  final AgentState state;
  final double size;
  final OrbMaterial? material;

  Color get _tint => switch (state) {
    AgentState.idle => VoiceOpsColors.primary,
    AgentState.thinking => VoiceOpsColors.primaryLight,
    AgentState.calling => VoiceOpsColors.success,
    AgentState.mapping => VoiceOpsColors.blue,
    AgentState.taskWorking => VoiceOpsColors.amber,
    AgentState.summarizing => VoiceOpsColors.amber,
    AgentState.celebrating => VoiceOpsColors.pink,
  };

  @override
  Widget build(BuildContext context) {
    final resolvedMaterial = material ?? OrbMaterialScope.of(context);
    final colors = resolvedMaterial == OrbMaterial.holographic
        ? VoiceOpsOrbColors.holographic
        : VoiceOpsOrbColors.chrome;
    final tint = _tint;

    return Semantics(
      image: true,
      label: 'Co-rider',
      value: state.label,
      child: AnimatedContainer(
        duration: VoiceOpsMotion.orbMorph,
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: SweepGradient(
            colors: [
              for (final color in colors) Color.lerp(color, tint, 0.25)!,
            ],
          ),
          boxShadow: [
            BoxShadow(
              color: tint.withValues(alpha: 0.4),
              blurRadius: 26,
              offset: const Offset(0, 10),
            ),
          ],
        ),
      ),
    );
  }
}
