import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/push_to_talk_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../../providers/agent_state_provider.dart';
import '../widgets/action_chips_grid.dart';

class VoiceScreen extends ConsumerStatefulWidget {
  const VoiceScreen({super.key});
  @override
  ConsumerState<VoiceScreen> createState() => _VoiceScreenState();
}

class _VoiceScreenState extends ConsumerState<VoiceScreen> {
  // Real driver commands (PRD v4.0 §7), never generic assistant actions.
  static const _chips = [
    ActionChipData(
      icon: TablerIcons.mapPin,
      label: 'Find my next stop',
      accent: VoiceOpsColors.blue,
    ),
    ActionChipData(
      icon: TablerIcons.listCheck,
      label: "What's left on my list",
      accent: VoiceOpsColors.amber,
    ),
    ActionChipData(
      icon: TablerIcons.phoneCall,
      label: 'Call the customer',
      accent: VoiceOpsColors.success,
    ),
    ActionChipData(
      icon: TablerIcons.chartBar,
      label: 'Give me my summary',
      accent: VoiceOpsColors.pink,
    ),
  ];

  static const _chipStates = [
    AgentState.mapping,
    AgentState.taskWorking,
    AgentState.calling,
    AgentState.summarizing,
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
  Widget build(BuildContext context) {
    final agentState = ref.watch(agentStateProvider);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  _MapPreview(state: agentState),
                  Padding(
                    padding: const EdgeInsets.all(VoiceOpsSpacing.gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _NextStopCard(),
                        const SizedBox(height: VoiceOpsSpacing.lg),
                        const _TranscriptCard(),
                        const SizedBox(height: VoiceOpsSpacing.lg),
                        Text('Quick actions', style: VoiceOpsText.title),
                        const SizedBox(height: VoiceOpsSpacing.sm),
                        ActionChipsGrid(chips: _chips, onSelect: _onChipTap),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Keep the primary control reachable while the operations scroll.
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VoiceOpsSpacing.md),
            child: Column(
              children: [
                const PushToTalkButton(),
                const SizedBox(height: VoiceOpsSpacing.sm),
                Text(
                  'Voice preview · no audio captured',
                  style: VoiceOpsText.caption,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Illustrative surface only: no location, map tiles or live route data.
class _MapPreview extends StatelessWidget {
  const _MapPreview({required this.state});
  final AgentState state;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('map-preview'),
      height: MediaQuery.sizeOf(context).height * 0.45,
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [VoiceOpsColors.overlay, VoiceOpsColors.canvas],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ExcludeSemantics(child: CustomPaint(painter: _MapGrid())),
            ),
            Positioned(
              top: VoiceOpsSpacing.lg,
              left: VoiceOpsSpacing.gutter,
              right: VoiceOpsSpacing.gutter,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your route, together', style: VoiceOpsText.headline),
                  const SizedBox(height: VoiceOpsSpacing.xs),
                  Text(
                    'Map preview · sample route',
                    style: VoiceOpsText.bodyMuted,
                  ),
                ],
              ),
            ),
            const Align(
              alignment: Alignment(0.65, -0.15),
              child: Icon(
                TablerIcons.mapPin,
                color: VoiceOpsColors.primaryLight,
                size: VoiceOpsSize.iconXl,
              ),
            ),
            Align(
              alignment: Alignment.bottomCenter,
              child: Padding(
                padding: const EdgeInsets.only(bottom: VoiceOpsSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    MascotDisplay(
                      state: state,
                      size: VoiceOpsSize.orbHero,
                      material: OrbMaterial.chrome,
                    ),
                    Text(
                      state.label ?? 'Your co-rider is ready',
                      style: VoiceOpsText.label,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NextStopCard extends StatelessWidget {
  const _NextStopCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: false,
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT STOP · SAMPLE', style: VoiceOpsText.caption),
          const SizedBox(height: VoiceOpsSpacing.sm),
          Text('24 Adeola Odeku Street', style: VoiceOpsText.title),
          Text('Victoria Island, Lagos', style: VoiceOpsText.bodyMuted),
          const SizedBox(height: VoiceOpsSpacing.md),
          Wrap(
            spacing: VoiceOpsSpacing.lg,
            runSpacing: VoiceOpsSpacing.sm,
            children: [
              Text('Customer: Ada O.', style: VoiceOpsText.label),
              Text('ETA · 8 min', style: VoiceOpsText.label),
            ],
          ),
        ],
      ),
    );
  }
}

class _TranscriptCard extends StatelessWidget {
  const _TranscriptCard();

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: false,
      shadow: false,
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CONVERSATION · SAMPLE', style: VoiceOpsText.caption),
          const SizedBox(height: VoiceOpsSpacing.md),
          Text('You', style: VoiceOpsText.label),
          Text('Where am I heading next?', style: VoiceOpsText.bodyMuted),
          const SizedBox(height: VoiceOpsSpacing.md),
          Text(
            'Co-rider',
            style: VoiceOpsText.label.copyWith(
              color: VoiceOpsColors.primaryLight,
            ),
          ),
          Text(
            'Your next stop is Ada on Adeola Odeku Street. '
            'You’re about 8 minutes away.',
            style: VoiceOpsText.body,
          ),
        ],
      ),
    );
  }
}

class _MapGrid extends CustomPainter {
  const _MapGrid();

  @override
  void paint(Canvas canvas, Size size) {
    final grid = Paint()
      ..color = VoiceOpsColors.divider
      ..strokeWidth = VoiceOpsGlass.borderWidth;
    for (double x = 0; x < size.width; x += VoiceOpsSpacing.xxl) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += VoiceOpsSpacing.xxl) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final route = Path()
      ..moveTo(size.width * 0.15, size.height * 0.7)
      ..lineTo(size.width * 0.15, size.height * 0.4)
      ..lineTo(size.width * 0.8, size.height * 0.4);
    canvas.drawPath(
      route,
      Paint()
        ..color = VoiceOpsColors.primaryTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = VoiceOpsSpacing.sm
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MapGrid oldDelegate) => false;
}
