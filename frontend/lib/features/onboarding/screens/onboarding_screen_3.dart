import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../widgets/fill_or_scroll.dart';

/// Onboarding screen 3, the Trust (PRD v4.0 §4.7, SDD v2.0 §4.3), over the
/// dark navy mood: the co-rider settles smaller and calmer, readiness is
/// confirmed, and the CTA hands the driver to the main app.
class OnboardingTrust extends StatelessWidget {
  const OnboardingTrust({super.key, required this.onStartDriving});

  static const headline = 'It knows your voice. Time to drive.';

  final VoidCallback onStartDriving;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: VoiceOpsSpacing.gutter),
      child: FillOrScroll(
        builder: (context, viewport) => Column(
          children: [
            const SizedBox(height: VoiceOpsSpacing.lg),
            const PillChip(
              icon: TablerIcons.check,
              label: 'Voice calibrated',
              accent: VoiceOpsColors.success,
            ),
            Expanded(
              // No breathing wrapper here: after the Hook's waking breath the
              // co-rider rests at its plain idle pulse.
              child: Center(
                child: MascotDisplay(
                  state: AgentState.idle,
                  size: math.min(VoiceOpsSize.orbHero, viewport.height * 0.22),
                ),
              ),
            ),
            Semantics(
              header: true,
              child: Text(
                headline,
                style: FillOrScroll.headlineFor(viewport),
                textAlign: TextAlign.center,
              ),
            ),
            const SizedBox(height: VoiceOpsSpacing.xl),
            const Row(
              children: [
                Expanded(
                  child: _Stat(
                    icon: TablerIcons.microphone,
                    label: 'Voice',
                    value: 'Ready',
                    accent: VoiceOpsColors.primaryLight,
                  ),
                ),
                SizedBox(width: VoiceOpsSpacing.sm),
                Expanded(
                  child: _Stat(
                    icon: TablerIcons.route,
                    label: 'Route',
                    value: 'Loaded',
                    accent: VoiceOpsColors.blue,
                  ),
                ),
                SizedBox(width: VoiceOpsSpacing.sm),
                Expanded(
                  child: _Stat(
                    icon: TablerIcons.handOff,
                    label: 'Hands',
                    value: 'Free',
                    accent: VoiceOpsColors.pink,
                  ),
                ),
              ],
            ),
            const SizedBox(height: VoiceOpsSpacing.lg),
            _CtaCard(onStartDriving: onStartDriving),
            const SizedBox(height: VoiceOpsSpacing.sm),
          ],
        ),
      ),
    );
  }
}

/// One readiness stat, read aloud as "Voice: Ready".
class _Stat extends StatelessWidget {
  const _Stat({
    required this.icon,
    required this.label,
    required this.value,
    required this.accent,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '$label: $value',
      excludeSemantics: true,
      child: GlassCard(
        frosted: false,
        shadow: false,
        padding: const EdgeInsets.all(VoiceOpsSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: VoiceOpsSize.iconXl,
              height: VoiceOpsSize.iconXl,
              decoration: BoxDecoration(shape: BoxShape.circle, color: accent),
              child: Icon(
                icon,
                size: VoiceOpsSize.iconSm,
                color: VoiceOpsColors.onAccent,
              ),
            ),
            const SizedBox(height: VoiceOpsSpacing.sm),
            Text(label.toUpperCase(), style: VoiceOpsText.caption),
            Text(value, style: VoiceOpsText.title),
          ],
        ),
      ),
    );
  }
}

/// Holographic card closing the flow: "Your voice, your co-rider" over the
/// "Start driving →" button.
class _CtaCard extends StatelessWidget {
  const _CtaCard({required this.onStartDriving});

  final VoidCallback onStartDriving;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      decoration: BoxDecoration(
        gradient: VoiceOpsMood.holographic,
        borderRadius: BorderRadius.circular(VoiceOpsRadius.card),
        boxShadow: VoiceOpsGlass.shadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Your voice, your co-rider',
            style: VoiceOpsText.headline.copyWith(color: VoiceOpsMood.ink),
          ),
          const SizedBox(height: VoiceOpsSpacing.md),
          PrimaryButton(
            label: 'Start driving',
            trailingIcon: TablerIcons.arrowRight,
            expand: true,
            onPressed: onStartDriving,
          ),
        ],
      ),
    );
  }
}
