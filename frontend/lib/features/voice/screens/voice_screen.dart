import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/theme/tokens.dart';
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
      icon: Icons.image_rounded,
      label: 'Create an image',
      iconBgColors: [Color(0xFFF9A8D4), Color(0xFFC084FC)],
    ),
    ActionChipData(
      icon: Icons.lightbulb_rounded,
      label: 'Give me ideas',
      iconBgColors: [Color(0xFFFDE68A), Color(0xFFF59E0B)],
    ),
    ActionChipData(
      icon: Icons.checklist_rounded,
      label: 'Do the task',
      iconBgColors: [Color(0xFF6EE7B7), Color(0xFF059669)],
    ),
    ActionChipData(
      icon: Icons.translate_rounded,
      label: 'Translate text',
      iconBgColors: [Color(0xFF7DD3FC), Color(0xFF3B82F6)],
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
        padding: const EdgeInsets.fromLTRB(22, 8, 22, 12),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _NavButton(icon: Icons.menu_rounded, onTap: () {}),
                _NavButton(icon: Icons.settings_rounded, onTap: () {}),
              ],
            ),
            const SizedBox(height: VoiceOpsSpacing.md),
            const GreetingWidget(name: 'Mary'),
            Expanded(
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MascotDisplay(state: agentState, size: 150),
                    if (agentState.label != null) ...[
                      const SizedBox(height: VoiceOpsSpacing.md),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.72),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: VoiceOpsColors.primaryLight.withOpacity(0.3),
                          ),
                        ),
                        child: Text(
                          agentState.label!.toUpperCase(),
                          style: VoiceOpsText.mascotLabel,
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
  const _NavButton({required this.icon, required this.onTap});
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.62),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: VoiceOpsColors.glassBorder),
        ),
        child: Icon(icon, size: 17, color: VoiceOpsColors.primary),
      ),
    );
  }
}
