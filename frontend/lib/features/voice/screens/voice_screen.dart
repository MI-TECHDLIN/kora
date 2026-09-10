import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/voice_input_bar.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../../providers/agent_state_provider.dart';
import '../widgets/action_chips_grid.dart';
import '../widgets/greeting_widget.dart';

class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});
  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  final _inputController = TextEditingController();

  static const _chips = [
    ActionChipData(
      icon: TablerIcons.photo,
      label: 'Create an image',
      accent: VoiceOpsColors.pink,
    ),
    ActionChipData(
      icon: TablerIcons.bulb,
      label: 'Give me ideas',
      accent: VoiceOpsColors.amber,
    ),
    ActionChipData(
      icon: TablerIcons.checklist,
      label: 'Do the task',
      accent: VoiceOpsColors.success,
    ),
    ActionChipData(
      icon: TablerIcons.language,
      label: 'Translate text',
      accent: VoiceOpsColors.blue,
    ),
  ];

  static const _chipStates = [
    AgentState.taskWorking,
    AgentState.thinking,
    AgentState.taskWorking,
    AgentState.translating,
  ];

  void _onChipTap(int i) {
    // Demo-only interaction until FastAPI is wired up in Checkpoint 2.
    ref.read(agentStateProvider.notifier).setState(AgentState.thinking);
    Future.delayed(const Duration(milliseconds: 900), () {
      if (!mounted) return;
      ref.read(agentStateProvider.notifier).setState(_chipStates[i]);
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        ref.read(agentStateProvider.notifier).reset();
      });
    });
  }

  @override
  void dispose() {
    _inputController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentStateProvider);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          VoiceOpsSpacing.gutter,
          VoiceOpsSpacing.sm,
          VoiceOpsSpacing.gutter,
          VoiceOpsSpacing.md,
        ),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavButton(
                  icon: TablerIcons.menu2,
                  label: 'Menu',
                  onTap: () {},
                ),
                _NavButton(
                  icon: TablerIcons.settings,
                  label: 'Settings',
                  onTap: () {},
                ),
              ],
            ),
            const SizedBox(height: VoiceOpsSpacing.md),
            const GreetingWidget(name: 'Mary'),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MascotDisplay(
                      state: agentState,
                      size: VoiceOpsSize.orbHero,
                    ),
                    if (agentState.label != null) ...[
                      const SizedBox(height: VoiceOpsSpacing.md),
                      GlassCard(
                        frosted: false,
                        shadow: false,
                        borderRadius: VoiceOpsRadius.pill,
                        fill: VoiceOpsColors.primaryTint,
                        padding: const EdgeInsets.symmetric(
                          horizontal: VoiceOpsSpacing.lg,
                          vertical: VoiceOpsSpacing.xs,
                        ),
                        child: Text(
                          agentState.label!.toUpperCase(),
                          style: VoiceOpsText.caption.copyWith(
                            color: VoiceOpsColors.primaryLight,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            ActionChipsGrid(chips: _chips, onSelect: _onChipTap),
            const SizedBox(height: VoiceOpsSpacing.md),
            VoiceInputBar(
              controller: _inputController,
              onMicTap: () => _onChipTap(1),
            ),
          ],
        ),
      ),
    );
  }
}

class _NavButton extends StatelessWidget {
  const _NavButton({
    required this.icon,
    required this.label,
    required this.onTap,
  });
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        child: SizedBox.square(
          dimension: VoiceOpsSize.touchTarget,
          child: GlassCard(
            frosted: false,
            shadow: false,
            borderRadius: VoiceOpsRadius.control,
            child: Icon(
              icon,
              size: VoiceOpsSize.iconMd,
              color: VoiceOpsColors.primaryLight,
            ),
          ),
        ),
      ),
    );
  }
}
