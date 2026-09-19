import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';
import '../../../app/router.dart';
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
      accent: KoraColors.blue,
    ),
    ActionChipData(
      icon: TablerIcons.listCheck,
      label: "What's left on my list",
      accent: KoraColors.amber,
    ),
    ActionChipData(
      icon: TablerIcons.phoneCall,
      label: 'Call the customer',
      accent: KoraColors.success,
    ),
    ActionChipData(
      icon: TablerIcons.chartBar,
      label: 'Give me my summary',
      accent: KoraColors.pink,
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
                    padding: const EdgeInsets.all(KoraSpacing.gutter),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const _NextStopCard(),
                        const SizedBox(height: KoraSpacing.lg),
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
              horizontal: KoraSpacing.gutter,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Quick actions', style: KoraText.title),
                const SizedBox(height: KoraSpacing.sm),
                ActionChipsRail(chips: _chips, onSelect: _onChipTap),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: KoraSpacing.md),
            child: Column(
              children: [
                const PushToTalkButton(),
                const SizedBox(height: KoraSpacing.sm),
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
                  style: KoraText.caption,
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
        MediaQuery.sizeOf(context).height < KoraMap.compactHeight;

    return SizedBox(
      key: const Key('map-preview'),
      height: compact
          ? KoraSize.mapPreviewCompact
          : KoraSize.mapPreview,
      width: double.infinity,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [KoraColors.overlay, KoraColors.canvas],
          ),
        ),
        child: Stack(
          children: [
            const Positioned.fill(
              child: ExcludeSemantics(child: CustomPaint(painter: _MapGrid())),
            ),
            // The profile lives behind this corner icon, not in the bottom
            // nav, stacked on the map preview instead of its own row.
            Positioned(
              top: KoraSpacing.sm,
              right: KoraSpacing.sm,
              child: IconButton(
                key: const Key('profile-button'),
                tooltip: 'Your profile',
                onPressed: () => context.go(AppRoutes.profile),
                constraints: const BoxConstraints(
                  minWidth: KoraSize.touchTarget,
                  minHeight: KoraSize.touchTarget,
                ),
                icon: const Icon(
                  TablerIcons.userCircle,
                  size: KoraSize.iconLg,
                  color: KoraColors.textPrimary,
                ),
              ),
            ),
            Positioned(
              top: KoraSpacing.lg,
              left: KoraSpacing.gutter,
              right: KoraSize.orbVoice + KoraSpacing.lg,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Your route, together', style: KoraText.headline),
                  const SizedBox(height: KoraSpacing.xs),
                  Text(
                    'Map preview · sample route',
                    style: KoraText.bodyMuted,
                  ),
                ],
              ),
            ),
            const Align(
              alignment: Alignment(0.65, -0.15),
              child: Icon(
                TablerIcons.mapPin,
                color: KoraColors.primaryLight,
                size: KoraSize.iconXl,
              ),
            ),
            Positioned(
              right: KoraSpacing.md,
              bottom: KoraSpacing.md,
              width: KoraSize.orbVoice,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  MascotDisplay(
                    state: state,
                    size: KoraSize.orbVoice,
                    material: OrbMaterial.chrome,
                  ),
                  Text(
                    state.label ?? 'Your co-rider is ready',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: KoraText.label,
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
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('NEXT STOP · SAMPLE', style: KoraText.caption),
          const SizedBox(height: KoraSpacing.sm),
          Text('1400 Lavaca Street', style: KoraText.title),
          Text('Downtown, Austin, TX', style: KoraText.bodyMuted),
          const SizedBox(height: KoraSpacing.md),
          Wrap(
            spacing: KoraSpacing.lg,
            runSpacing: KoraSpacing.sm,
            children: [
              Text('Customer: Ada O.', style: KoraText.label),
              Text('ETA · 8 min', style: KoraText.label),
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
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            lines.isEmpty ? 'CONVERSATION · SAMPLE' : 'CONVERSATION',
            style: KoraText.caption,
          ),
          if (lines.isEmpty) ...[
            const SizedBox(height: KoraSpacing.md),
            const _TranscriptLineView(
              TranscriptLine(SpeakerRole.driver, 'Where am I heading next?'),
            ),
            const SizedBox(height: KoraSpacing.md),
            const _TranscriptLineView(
              TranscriptLine(
                SpeakerRole.agent,
                'Your next stop is Ada on Lavaca Street. '
                'You’re about 8 minutes away.',
              ),
            ),
          ],
          for (final line in shown) ...[
            const SizedBox(height: KoraSpacing.md),
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
              ? KoraText.label
              : KoraText.label.copyWith(color: KoraColors.primaryLight),
        ),
        Text(
          line.text,
          style: isDriver ? KoraText.bodyMuted : KoraText.body,
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
      ..color = KoraColors.divider
      ..strokeWidth = KoraGlass.borderWidth;
    for (double x = 0; x < size.width; x += KoraSpacing.xxl) {
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), grid);
    }
    for (double y = 0; y < size.height; y += KoraSpacing.xxl) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), grid);
    }
    final route = Path()
      ..moveTo(size.width * 0.15, size.height * 0.7)
      ..lineTo(size.width * 0.15, size.height * 0.4)
      ..lineTo(size.width * 0.8, size.height * 0.4);
    canvas.drawPath(
      route,
      Paint()
        ..color = KoraColors.primaryTint
        ..style = PaintingStyle.stroke
        ..strokeWidth = KoraSpacing.sm
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(_MapGrid oldDelegate) => false;
}
