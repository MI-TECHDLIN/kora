import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/agent_state_provider.dart';
import '../providers/navigation_provider.dart';
import 'mascot_display.dart';

/// Global mascot layer (RootStack §5.1). Hidden on the Voice tab because
/// VoiceScreen renders its own inline mascot; floats as a bubble on
/// Map/Summary/Settings.
class MascotOverlay extends ConsumerWidget {
  const MascotOverlay({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tab = ref.watch(navigationProvider);
    final agentState = ref.watch(agentStateProvider);

    if (tab == NavigationNotifier.voice) return const SizedBox.shrink();

    final size = tab == NavigationNotifier.settings ? 40.0 : 60.0;
    final alignRight = tab == NavigationNotifier.settings;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 400),
      curve: Curves.easeInOut,
      top: 60,
      left: alignRight ? null : 20,
      right: alignRight ? 20 : null,
      child: MascotDisplay(state: agentState, size: size),
    );
  }
}
