import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/primary_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../../providers/onboarding_provider.dart';

/// Full 3-screen mascot-emotion flow (PRD v4.0 §4.7) lands in Checkpoint 3.
/// The co-rider here takes the holographic material from the onboarding
/// route's OrbMaterialScope.
class OnboardingFlow extends ConsumerWidget {
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(VoiceOpsSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const MascotDisplay(
              state: AgentState.idle,
              size: VoiceOpsSize.orbHero,
            ),
            const SizedBox(height: VoiceOpsSpacing.xl),
            Text(
              'Onboarding — coming in Checkpoint 3',
              style: VoiceOpsText.headline,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VoiceOpsSpacing.xl),
            PrimaryButton(
              label: 'Start Driving',
              onPressed: () => ref.read(onboardingProvider.notifier).complete(),
            ),
          ],
        ),
      ),
    );
  }
}
