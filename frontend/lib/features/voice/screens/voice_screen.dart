import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import '../../../core/realtime/voice_events.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/push_to_talk_button.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../../providers/agent_state_provider.dart';
import '../../../providers/push_to_talk_provider.dart';
import '../../../providers/transcript_provider.dart';
import '../widgets/action_chips_rail.dart';

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
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          // Keep common commands beside the primary control while the
          // operational detail above scrolls independently.
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: VoiceOpsSpacing.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick actions', style: VoiceOpsText.title),
                const SizedBox(height: VoiceOpsSpacing.sm),
                ActionChipsRail(chips: _chips, onSelect: _onChipTap),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: VoiceOpsSpacing.md),
            child: Column(
              children: [
                const PushToTalkButton(),
                const SizedBox(height: VoiceOpsSpacing.sm),
                Text(
                  switch (ref.watch(pushToTalkProvider)) {
                    PushToTalkState.idle => 'Tap to talk to your co-rider',
                    PushToTalkState.recording => 'Listening · tap to end',
                    PushToTalkState.processing => 'Working on it…',
                    PushToTalkState.speaking =>
                      ref.watch(micLiveProvider)
                          ? 'Talk or tap to interrupt'
                          : 'Tap to interrupt',
                  },
                  key: const Key('ptt-hint'),
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
    final compact =
        MediaQuery.sizeOf(context).height < VoiceOpsMap.compactHeight;

    return SizedBox(
      key: const Key('map-preview'),
      height: compact
          ? VoiceOpsSize.mapPreviewCompact
          : VoiceOpsSize.mapPreview,
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
              right: VoiceOpsSize.orbVoice + VoiceOpsSpacing.lg,
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
            Positioned(
              right: VoiceOpsSpacing.md,
              bottom: VoiceOpsSpacing.md,
              width: VoiceOpsSize.orbVoice,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MascotDisplay(
                    state: state,
                    size: VoiceOpsSize.orbVoice,
                    material: OrbMaterial.chrome,
                  ),
                  Text(
                    state.label ?? 'Your co-rider is ready',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: VoiceOpsText.label,
                  ),
                ],
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
          Text('1400 Lavaca Street', style: VoiceOpsText.title),
          Text('Downtown, Austin, TX', style: VoiceOpsText.bodyMuted),
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

/// The conversation from the voice session's `transcript` events; the
/// sample exchange shows until the driver first talks.
class _TranscriptCard extends ConsumerWidget {
  const _TranscriptCard();

  /// The latest lines only: the card is a glance, not a history.
  static const _visibleLines = 4;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lines = ref.watch(transcriptProvider);
    final shown = lines.length > _visibleLines
        ? lines.sublist(lines.length - _visibleLines)
        : lines;
    return GlassCard(
      frosted: false,
      shadow: false,
      padding: const EdgeInsets.all(VoiceOpsSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lines.isEmpty ? 'CONVERSATION · SAMPLE' : 'CONVERSATION',
            style: VoiceOpsText.caption,
          ),
          if (lines.isEmpty) ...[
            const SizedBox(height: VoiceOpsSpacing.md),
            const _TranscriptLineView(
              TranscriptLine(SpeakerRole.driver, 'Where am I heading next?'),
            ),
            const SizedBox(height: VoiceOpsSpacing.md),
            const _TranscriptLineView(
              TranscriptLine(
                SpeakerRole.agent,
                'Your next stop is Ada on Lavaca Street. '
                'You’re about 8 minutes away.',
              ),
            ),
          ],
          for (final line in shown) ...[
            const SizedBox(height: VoiceOpsSpacing.md),
            _TranscriptLineView(line),
          ],
        ],
      ),
    );
  }
}

class _TranscriptLineView extends StatelessWidget {
  const _TranscriptLineView(this.line);
  final TranscriptLine line;

  @override
  Widget build(BuildContext context) {
    final isDriver = line.role == SpeakerRole.driver;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          isDriver ? 'You' : 'Co-rider',
          style: isDriver
              ? VoiceOpsText.label
              : VoiceOpsText.label.copyWith(color: VoiceOpsColors.primaryLight),
        ),
        Text(
          line.text,
          style: isDriver ? VoiceOpsText.bodyMuted : VoiceOpsText.body,
        ),
      ],
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
