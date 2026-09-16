import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../core/realtime/voice_events.dart';
import '../core/theme/tokens.dart';
import '../core/widgets/glass_card.dart';
import '../providers/proactive_alert_provider.dart';

/// The risk engine speaking up: traffic on the route, a delivery window
/// slipping, the van standing still too long. The co-rider says the same
/// sentence out loud; this is the version the driver can glance at.
///
/// A reroute suggestion adds the ETA comparison, because "saves 8 minutes"
/// is the whole decision — the alternate line itself is already on the map.
class ProactiveAlertCard extends ConsumerWidget {
  const ProactiveAlertCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final alert = ref.watch(proactiveAlertProvider);
    if (alert == null) return const SizedBox.shrink();
    final accent = _accentFor(alert.severity);

    return GlassCard(
      key: const Key('proactive-alert'),
      fill: VoiceOpsColors.raised.withValues(alpha: 0.92),
      border: Border.all(
        color: accent.withValues(alpha: 0.5),
        width: VoiceOpsGlass.borderWidth,
      ),
      padding: const EdgeInsets.fromLTRB(
        VoiceOpsSpacing.md,
        VoiceOpsSpacing.md,
        VoiceOpsSpacing.sm,
        VoiceOpsSpacing.md,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                _iconFor(alert.riskType),
                size: VoiceOpsSize.iconMd,
                color: accent,
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _labelFor(alert.riskType),
                      style: VoiceOpsText.caption,
                    ),
                    const SizedBox(height: VoiceOpsSpacing.xs),
                    Text(alert.message, style: VoiceOpsText.body),
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss',
                excludeSemantics: true,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: ref.read(proactiveAlertProvider.notifier).dismiss,
                  child: const SizedBox(
                    width: VoiceOpsSize.touchTarget,
                    height: VoiceOpsSize.touchTarget,
                    child: Icon(
                      TablerIcons.x,
                      size: VoiceOpsSize.iconSm,
                      color: VoiceOpsColors.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
          if (alert.routeSuggestion case final suggestion?)
            Padding(
              padding: const EdgeInsets.only(top: VoiceOpsSpacing.sm),
              child: _EtaComparison(suggestion: suggestion),
            ),
        ],
      ),
    );
  }

  static Color _accentFor(RiskSeverity severity) => switch (severity) {
    RiskSeverity.critical => VoiceOpsColors.danger,
    RiskSeverity.high => VoiceOpsColors.amber,
    RiskSeverity.medium || RiskSeverity.low => VoiceOpsColors.primaryLight,
  };

  static IconData _iconFor(RiskType type) => switch (type) {
    RiskType.routeDeviation => TablerIcons.routeAltLeft,
    RiskType.excessiveIdle => TablerIcons.playerPause,
    RiskType.timeWindowRisk ||
    RiskType.lateDelivery => TablerIcons.clockExclamation,
    RiskType.customerUnavailable => TablerIcons.userQuestion,
    RiskType.driverNoResponse || RiskType.unknown => TablerIcons.alertTriangle,
  };

  static String _labelFor(RiskType type) => switch (type) {
    RiskType.routeDeviation => 'FASTER ROUTE',
    RiskType.excessiveIdle => 'STOPPED A WHILE',
    RiskType.timeWindowRisk => 'WINDOW AT RISK',
    RiskType.lateDelivery => 'RUNNING LATE',
    RiskType.customerUnavailable => 'CUSTOMER UNAVAILABLE',
    RiskType.driverNoResponse || RiskType.unknown => 'HEADS UP',
  };
}

/// "20 min -> 12 min - saves 8". Whichever half the server sent is shown;
/// the row disappears entirely when it sent neither.
class _EtaComparison extends StatelessWidget {
  const _EtaComparison({required this.suggestion});

  final RouteSuggestion suggestion;

  @override
  Widget build(BuildContext context) {
    final current = suggestion.currentEtaMinutes;
    final alternate = suggestion.etaMinutes;
    final savings = suggestion.savingsMinutes;
    if (current == null && alternate == null) return const SizedBox.shrink();

    return Row(
      key: const Key('proactive-alert-eta'),
      children: [
        if (current != null) ...[
          Text(
            '$current min',
            style: VoiceOpsText.label.copyWith(
              color: VoiceOpsColors.textMuted,
              decoration: alternate == null
                  ? TextDecoration.none
                  : TextDecoration.lineThrough,
              decorationColor: VoiceOpsColors.textMuted,
            ),
          ),
          if (alternate != null) ...[
            const SizedBox(width: VoiceOpsSpacing.sm),
            const Icon(
              TablerIcons.arrowNarrowRight,
              size: VoiceOpsSize.iconSm,
              color: VoiceOpsColors.textFaint,
            ),
            const SizedBox(width: VoiceOpsSpacing.sm),
          ],
        ],
        if (alternate != null)
          Text(
            '$alternate min',
            style: VoiceOpsText.label.copyWith(
              color: VoiceOpsColors.primaryLight,
            ),
          ),
        if (savings != null) ...[
          const SizedBox(width: VoiceOpsSpacing.sm),
          Flexible(
            child: Text(
              '- saves $savings min',
              style: VoiceOpsText.label.copyWith(color: VoiceOpsColors.success),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ],
    );
  }
}
