import 'package:flutter/material.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/driver_vehicle_row.dart';
import '../../../core/widgets/glass_card.dart';
import '../data/map_route.dart';

/// The Map tab's bottom sheet: the stop being driven to with its trip
/// stats, and the driver's vehicle. Tap the handle to fold it down to the
/// headline so more of the map shows.
class RouteCard extends StatelessWidget {
  const RouteCard({
    super.key,
    required this.route,
    required this.stop,
    required this.expanded,
    required this.onToggle,
  });

  final MapRoute? route;

  /// The stop shown: the route's target unless the driver tapped a pin.
  final RouteStop? stop;
  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final route = this.route;
    return GlassCard(
      key: const Key('route-card'),
      borderRadius: VoiceOpsRadius.sheet,
      fill: VoiceOpsColors.raised.withValues(alpha: 0.9),
      padding: const EdgeInsets.fromLTRB(
        VoiceOpsSpacing.lg,
        0,
        VoiceOpsSpacing.lg,
        VoiceOpsSpacing.lg,
      ),
      child: AnimatedSize(
        duration: VoiceOpsMotion.base,
        curve: VoiceOpsMotion.standard,
        alignment: Alignment.topCenter,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // The handle and headline together are the fold toggle, so the
            // target is well over the minimum touch size.
            Semantics(
              button: true,
              label: expanded ? 'Show less' : 'Show trip details',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onToggle,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const _Handle(),
                    if (route == null)
                      const _NoRoute()
                    else
                      _StopHeadline(route: route, stop: stop),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              if (route != null) ...[
                const SizedBox(height: VoiceOpsSpacing.lg),
                if (route.hasTripStats)
                  _TripStats(route: route)
                else
                  const _NoRoadRoute(),
              ],
              const SizedBox(height: VoiceOpsSpacing.lg),
              const Divider(height: 1, color: VoiceOpsColors.divider),
              const SizedBox(height: VoiceOpsSpacing.md),
              const DriverVehicleRow(),
            ],
          ],
        ),
      ),
    );
  }
}

class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: VoiceOpsSpacing.xl,
      child: Center(
        child: Container(
          width: VoiceOpsSpacing.xxl,
          height: VoiceOpsSpacing.xs,
          decoration: BoxDecoration(
            color: VoiceOpsColors.textFaint,
            borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
          ),
        ),
      ),
    );
  }
}

/// Empty state: no route yet, and how to get one.
class _NoRoute extends StatelessWidget {
  const _NoRoute();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('NO ROUTE YET', style: VoiceOpsText.caption),
        const SizedBox(height: VoiceOpsSpacing.xs),
        Text('Ask your co-rider for directions', style: VoiceOpsText.title),
        const SizedBox(height: VoiceOpsSpacing.xs),
        Text(
          'Say "take me to my next stop" and the route draws here.',
          style: VoiceOpsText.bodyMuted,
        ),
      ],
    );
  }
}

class _StopHeadline extends StatelessWidget {
  const _StopHeadline({required this.route, required this.stop});
  final MapRoute route;
  final RouteStop? stop;

  @override
  Widget build(BuildContext context) {
    final stop = this.stop;
    final isTarget = stop == null || stop.deliveryId == route.deliveryId;
    final sequence = stop?.sequence;
    final eyebrow = [
      isTarget ? 'NEXT STOP' : 'STOP',
      if (sequence != null) '$sequence',
    ].join(' · ');
    final eta = route.etaLabel;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(eyebrow, style: VoiceOpsText.caption)),
            if (isTarget && eta != null)
              _Pill(icon: TablerIcons.clock, text: eta),
          ],
        ),
        const SizedBox(height: VoiceOpsSpacing.xs),
        Text(
          stop?.recipientName ?? stop?.address ?? 'Your next stop',
          style: VoiceOpsText.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (stop?.recipientName != null && stop?.address != null)
          Text(
            stop!.address!,
            style: VoiceOpsText.bodyMuted,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
      ],
    );
  }
}

/// Directions found no road route (`polyline: ""`, null stats): the pin
/// still marks the stop, so say why there is no line or drive time.
class _NoRoadRoute extends StatelessWidget {
  const _NoRoadRoute();

  @override
  Widget build(BuildContext context) {
    return Row(
      key: const Key('no-road-route'),
      children: [
        const Icon(
          TablerIcons.routeOff,
          size: VoiceOpsSize.iconSm,
          color: VoiceOpsColors.textMuted,
        ),
        const SizedBox(width: VoiceOpsSpacing.sm),
        Expanded(
          child: Text(
            'No road route found. The pin marks your stop.',
            style: VoiceOpsText.bodyMuted,
          ),
        ),
      ],
    );
  }
}

class _TripStats extends StatelessWidget {
  const _TripStats({required this.route});
  final MapRoute route;

  @override
  Widget build(BuildContext context) {
    final distance = route.distanceKm;
    final minutes = route.durationMins;
    final summary = route.summary;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: _StatTile(
                icon: TablerIcons.route,
                value: distance == null ? '—' : '${_km(distance)} km',
                label: 'Distance',
              ),
            ),
            const SizedBox(width: VoiceOpsSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: TablerIcons.clock,
                value: minutes == null ? '—' : '$minutes min',
                label: 'Drive time',
              ),
            ),
            const SizedBox(width: VoiceOpsSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: TablerIcons.mapPins,
                value: '${route.stops.length}',
                label: route.stops.length == 1 ? 'Stop' : 'Stops',
              ),
            ),
          ],
        ),
        if (summary != null && summary.isNotEmpty) ...[
          const SizedBox(height: VoiceOpsSpacing.md),
          Row(
            children: [
              const Icon(
                TablerIcons.roadSign,
                size: VoiceOpsSize.iconSm,
                color: VoiceOpsColors.textMuted,
              ),
              const SizedBox(width: VoiceOpsSpacing.sm),
              Expanded(
                child: Text('via $summary', style: VoiceOpsText.bodyMuted),
              ),
            ],
          ),
        ],
      ],
    );
  }

  static String _km(double km) =>
      km >= 10 ? km.round().toString() : km.toStringAsFixed(1);
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return GlassCard(
      frosted: false,
      shadow: false,
      borderRadius: VoiceOpsRadius.control,
      padding: const EdgeInsets.all(VoiceOpsSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: VoiceOpsSize.iconMd,
            color: VoiceOpsColors.primaryLight,
          ),
          const SizedBox(height: VoiceOpsSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: VoiceOpsText.title),
          ),
          Text(label, style: VoiceOpsText.caption),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.text});
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: VoiceOpsSpacing.md,
        vertical: VoiceOpsSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: VoiceOpsColors.primaryTint,
        borderRadius: BorderRadius.circular(VoiceOpsRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: VoiceOpsSize.iconSm,
            color: VoiceOpsColors.primaryLight,
          ),
          const SizedBox(width: VoiceOpsSpacing.xs),
          Text(
            text,
            style: VoiceOpsText.label.copyWith(
              color: VoiceOpsColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
