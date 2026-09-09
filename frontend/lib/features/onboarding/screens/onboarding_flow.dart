import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/tokens.dart';
import '../../../providers/onboarding_provider.dart';

/// Full 3-screen mascot-emotion flow (PRD v4.0 §4.7) lands in Checkpoint 3.
class OnboardingFlow extends ConsumerWidget {
  const OnboardingFlow({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Onboarding — coming in Checkpoint 3',
              style: VoiceOpsText.greetingLarge,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: VoiceOpsSpacing.xl),
            ElevatedButton(
              onPressed: () => ref.read(onboardingProvider.notifier).complete(),
              style: ElevatedButton.styleFrom(
                backgroundColor: VoiceOpsColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VoiceOpsRadius.lg),
                ),
              ),
              child: const Text('Start Driving'),
            ),
          ],
        ),
      ),
    );
  }
}
