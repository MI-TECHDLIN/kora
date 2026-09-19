import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/pill_chip.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../widgets/breathing.dart';
import '../widgets/fill_or_scroll.dart';

/// Onboarding screen 1, the Hook (PRD v4.0 §4.7, SDD v2.0 §4.1), over the
/// dark navy mood: the co-rider wakes, large and breathing gently at rest.
class OnboardingHook extends StatelessWidget {
  const OnboardingHook({super.key});

  static const headline = "Say the word. It's already moving.";
  static const subtext =
      'One sentence starts your whole shift — no taps, no glancing down.';

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: KoraSpacing.gutter),
      child: FillOrScroll(
        builder: (context, viewport) => Column(
          children: [
            const SizedBox(height: KoraSpacing.lg),
            const PillChip(
              icon: TablerIcons.sparkles,
              label: 'Waking up your co-rider',
            ),
            Expanded(
              child: Center(
                child: Breathing(
                  child: MascotDisplay(
                    state: AgentState.idle,
                    size: math.min(
                      KoraSize.orbOnboarding,
                      viewport.height * 0.36,
                    ),
                  ),
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
            const SizedBox(height: KoraSpacing.md),
            Text(
              subtext,
              style: KoraText.bodyMuted,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: KoraSpacing.xl),
          ],
        ),
      ),
    );
  }
}
