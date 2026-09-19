import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../app/router.dart';
import '../core/theme/tokens.dart';
import '../providers/agent_state_provider.dart';
import '../providers/navigation_provider.dart';
import 'mascot_display.dart';

/// Global co-rider layer (RootStack §5.1). Hidden on the Voice tab because
/// VoiceScreen renders its own inline co-rider, and hidden outside the main
/// shell (onboarding); floats as a bubble on Map/Summary/Settings.
class MascotOverlay extends ConsumerWidget {
  const MascotOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(activeTabProvider);
    final agentState = ref.watch(agentStateProvider);

    if (tab == null || tab == MainTab.voice) return const SizedBox.shrink();

    final alignRight = tab == MainTab.settings;
    final size = alignRight
        ? KoraSize.orbBubbleSmall
        : KoraSize.orbBubble;

    return AnimatedPositioned(
      duration: KoraMotion.slow,
      curve: KoraMotion.emphasized,
      top: MediaQuery.paddingOf(context).top + KoraSpacing.md,
      left: alignRight ? null : KoraSpacing.gutter,
      right: alignRight ? KoraSpacing.gutter : null,
      // The overlay sits above the router, outside the shell's scope, so
      // it names its material explicitly: main app = chrome.
      child: MascotDisplay(
        state: agentState,
        size: size,
        material: OrbMaterial.chrome,
      ),
    );
  }
}
