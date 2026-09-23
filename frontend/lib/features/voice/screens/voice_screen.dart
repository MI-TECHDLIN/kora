import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../app/router.dart';
import '../../../core/realtime/voice_events.dart';
import '../../../core/theme/tokens.dart';
import '../../../core/wake/wake_word_service.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../core/widgets/push_to_talk_button.dart';
import '../../../features/map/data/location_source.dart';
import '../../../features/map/data/map_route.dart';
import '../../../mascot/mascot_display.dart';
import '../../../mascot/mascot_state.dart';
import '../../../providers/agent_state_provider.dart';
import '../../../providers/home_preferences_provider.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/map_route_provider.dart';
import '../../../providers/push_to_talk_provider.dart';
import '../../../providers/shift_provider.dart';
import '../../../providers/transcript_provider.dart';
import '../../../providers/voice_session_provider.dart';
import '../../../providers/wake_word_provider.dart';
import '../widgets/action_chips_rail.dart';
import '../widgets/next_orders_card.dart';

class VoiceScreen extends ConsumerWidget {
  const VoiceScreen({super.key});

  // Real driver commands from PRD v4.0 §7. Selecting one starts the voice
  // session so the driver can say it; no local demo state is manufactured.
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

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final agentState = ref.watch(agentStateProvider);
    final preferences = ref.watch(homePreferencesProvider);

    return SafeArea(
      child: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(
                KoraSpacing.gutter,
                KoraSpacing.lg,
                KoraSpacing.gutter,
                KoraSpacing.md,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _HomeStatusCard(state: agentState),
                  // The one-line target sits first so it stays in view.
                  if (preferences.targetEnabled) const TargetIndicator(),
                  if (preferences.nextOrdersEnabled) const NextOrdersCard(),
                  if (preferences.locationEnabled) ...[
                    const SizedBox(height: KoraSpacing.lg),
                    const _LocationCard(),
                  ],
                  if (preferences.conversationEnabled) ...[
                    const SizedBox(height: KoraSpacing.lg),
                    const _TranscriptCard(),
                  ],
                  if (preferences.quickActionsEnabled) ...[
                    const SizedBox(height: KoraSpacing.xl),
                    Text('Quick Actions', style: KoraText.title),
                    const SizedBox(height: KoraSpacing.sm),
                    ActionChipsRail(
                      chips: _chips,
                      onSelect: (_) => unawaited(
                        ref.read(voiceSessionProvider.notifier).startTalking(),
                      ),
                    ),
                  ],
                ],
              ),
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
                    PushToTalkState.idle =>
                      ref.watch(wakeWordControllerProvider) ==
                              WakeWordStatus.listening
                          ? 'Say “Kora” or tap to talk'
                          : 'Tap to talk to your co-rider',
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

/// Home's calm operational overview. It contains only session and route state
/// already received by the app, with an intentional empty state before work.
class _HomeStatusCard extends ConsumerWidget {
  const _HomeStatusCard({required this.state});

  final AgentState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final shiftActive = ref.watch(shiftProvider) != null;
    final route = ref.watch(mapRouteProvider);
    final stop = route?.target;

    return GlassCard(
      key: const Key('home-status-card'),
      frosted: false,
      fill: KoraColors.raised.withValues(alpha: 0.84),
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(
                shiftActive ? TablerIcons.route : TablerIcons.sparkles,
                size: KoraSize.iconSm,
                color: KoraColors.primaryLight,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Expanded(
                child: Text(
                  shiftActive ? 'SHIFT ACTIVE' : 'READY FOR YOUR SHIFT',
                  style: KoraText.caption,
                ),
              ),
              IconButton(
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
            ],
          ),
          const SizedBox(height: KoraSpacing.sm),
          Center(
            child: MascotDisplay(
              state: state,
              size: KoraSize.orbHero,
              material: OrbMaterial.chrome,
            ),
          ),
          const SizedBox(height: KoraSpacing.sm),
          Text(
            state.label ?? 'Ready when you are',
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: KoraText.title,
          ),
          const SizedBox(height: KoraSpacing.lg),
          const Divider(height: 1, color: KoraColors.divider),
          const SizedBox(height: KoraSpacing.lg),
          if (stop == null)
            const _NoActiveRoute()
          else
            _NextStop(route: route!, stop: stop),
        ],
      ),
    );
  }
}

class _NoActiveRoute extends StatelessWidget {
  const _NoActiveRoute();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('home-status-empty'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(
          TablerIcons.routeOff,
          size: KoraSize.iconLg,
          color: KoraColors.textMuted,
        ),
        const SizedBox(width: KoraSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('No active route', style: KoraText.label),
              const SizedBox(height: KoraSpacing.xs),
              Text(
                'Ask Kora when you’re ready for your next stop.',
                style: KoraText.bodyMuted,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _NextStop extends StatelessWidget {
  const _NextStop({required this.route, required this.stop});

  final MapRoute route;
  final RouteStop stop;

  @override
  Widget build(BuildContext context) {
    final sequence = stop.sequence;
    final eta = route.etaLabel;
    return Column(
      key: const Key('home-status-populated'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                ['NEXT STOP', if (sequence != null) '$sequence'].join(' · '),
                style: KoraText.caption,
              ),
            ),
            if (eta != null) ...[
              const Icon(
                TablerIcons.clock,
                size: KoraSize.iconSm,
                color: KoraColors.textMuted,
              ),
              const SizedBox(width: KoraSpacing.xs),
              Text(eta, style: KoraText.label),
            ],
          ],
        ),
        const SizedBox(height: KoraSpacing.sm),
        Text(
          stop.recipientName ?? stop.address ?? 'Your next stop',
          style: KoraText.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (stop.recipientName != null && stop.address != null) ...[
          const SizedBox(height: KoraSpacing.xs),
          Text(
            stop.address!,
            style: KoraText.bodyMuted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ],
    );
  }
}

class _LocationCard extends ConsumerWidget {
  const _LocationCard();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final location = ref.watch(locationProvider);
    return GlassCard(
      key: const Key('home-location'),
      frosted: false,
      shadow: false,
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            TablerIcons.currentLocation,
            size: KoraSize.iconLg,
            color: KoraColors.blue,
          ),
          const SizedBox(width: KoraSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CURRENT LOCATION', style: KoraText.caption),
                const SizedBox(height: KoraSpacing.xs),
                switch (location) {
                  AsyncData(:final value) => _LocationFixView(fix: value),
                  AsyncError(:final error) => _LocationErrorView(error: error),
                  _ => Text('Finding your location…', style: KoraText.body),
                },
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LocationFixView extends StatelessWidget {
  const _LocationFixView({required this.fix});

  final LocationFix fix;

  @override
  Widget build(BuildContext context) {
    final accuracy = fix.accuracy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Location ready', style: KoraText.label),
        const SizedBox(height: KoraSpacing.xs),
        Text(
          '${fix.point.latitude.toStringAsFixed(5)}, '
          '${fix.point.longitude.toStringAsFixed(5)}'
          '${accuracy == null ? '' : ' · ±${accuracy.round()} m'}',
          style: KoraText.bodyMuted,
        ),
      ],
    );
  }
}

class _LocationErrorView extends StatelessWidget {
  const _LocationErrorView({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    final message = error is LocationUnavailable
        ? (error as LocationUnavailable).message
        : const LocationUnavailable(LocationProblem.unavailable).message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(message, style: KoraText.bodyMuted),
        const SizedBox(height: KoraSpacing.sm),
        TextButton.icon(
          onPressed: () => context.go(AppRoutes.map),
          icon: const Icon(TablerIcons.map2, size: KoraSize.iconSm),
          label: const Text('Open map'),
        ),
      ],
    );
  }
}

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
      key: const Key('home-conversation'),
      frosted: false,
      shadow: false,
      padding: const EdgeInsets.all(KoraSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CONVERSATION', style: KoraText.caption),
          if (shown.isEmpty) ...[
            const SizedBox(height: KoraSpacing.md),
            Text('No conversation yet', style: KoraText.label),
            const SizedBox(height: KoraSpacing.xs),
            Text(
              'Your conversation with Kora will appear here.',
              style: KoraText.bodyMuted,
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
        Text(line.text, style: isDriver ? KoraText.bodyMuted : KoraText.body),
      ],
    );
  }
}
