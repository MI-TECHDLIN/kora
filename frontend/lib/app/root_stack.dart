import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../core/widgets/gradient_orb_bg.dart';
import '../features/onboarding/screens/onboarding_flow.dart';
import '../mascot/mascot_overlay.dart';
import '../overlays/task_progress_card.dart';
import '../providers/onboarding_provider.dart';
import 'main_navigator.dart';

/// A Stack, not a plain Navigator — so global overlays sit above every
/// screen at once. SDD v2.0 §2.1.
class RootStack extends ConsumerWidget {
  const RootStack({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final showOnboarding = ref.watch(onboardingProvider);

    return GradientOrbBackground(
      child: Stack(
        children: [
          showOnboarding ? const OnboardingFlow() : const MainNavigator(),
          const MascotOverlay(),
          const TaskProgressCard(),
        ],
      ),
    );
  }
}
