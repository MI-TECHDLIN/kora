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
      borderRadius: KoraRadius.sheet,
      fill: KoraColors.raised.withValues(alpha: 0.9),
      padding: const EdgeInsets.fromLTRB(
        KoraSpacing.lg,
        0,
        KoraSpacing.lg,
        KoraSpacing.lg,
      ),
      child: AnimatedSize(
        duration: KoraMotion.base,
        curve: KoraMotion.standard,
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
                const SizedBox(height: KoraSpacing.lg),
                if (route.hasTripStats)
                  _TripStats(route: route)
                else
                  const _NoRoadRoute(),
              ],
              const SizedBox(height: KoraSpacing.lg),
              const Divider(height: 1, color: KoraColors.divider),
              const SizedBox(height: KoraSpacing.md),
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
      height: KoraSpacing.xl,
      child: Center(
        child: Container(
          width: KoraSpacing.xxl,
          height: KoraSpacing.xs,
          decoration: BoxDecoration(
            color: KoraColors.textFaint,
            borderRadius: BorderRadius.circular(KoraRadius.pill),
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
        Text('NO ROUTE YET', style: KoraText.caption),
        const SizedBox(height: KoraSpacing.xs),
        Text('Ask your co-rider for directions', style: KoraText.title),
        const SizedBox(height: KoraSpacing.xs),
        Text(
          'Say "take me to my next stop" and the route draws here.',
          style: KoraText.bodyMuted,
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
            Expanded(child: Text(eyebrow, style: KoraText.caption)),
            if (isTarget && eta != null)
              _Pill(icon: TablerIcons.clock, text: eta),
          ],
        ),
        const SizedBox(height: KoraSpacing.xs),
        Text(
          stop?.recipientName ?? stop?.address ?? 'Your next stop',
          style: KoraText.headline,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        if (stop?.recipientName != null && stop?.address != null)
          Text(
            stop!.address!,
            style: KoraText.bodyMuted,
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
          size: KoraSize.iconSm,
          color: KoraColors.textMuted,
        ),
        const SizedBox(width: KoraSpacing.sm),
        Expanded(
          child: Text(
            'No road route found. The pin marks your stop.',
            style: KoraText.bodyMuted,
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
            const SizedBox(width: KoraSpacing.sm),
            Expanded(
              child: _StatTile(
                icon: TablerIcons.clock,
                value: minutes == null ? '—' : '$minutes min',
                label: 'Drive time',
              ),
            ),
            const SizedBox(width: KoraSpacing.sm),
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
          const SizedBox(height: KoraSpacing.md),
          Row(
            children: [
              const Icon(
                TablerIcons.roadSign,
                size: KoraSize.iconSm,
                color: KoraColors.textMuted,
              ),
              const SizedBox(width: KoraSpacing.sm),
              Expanded(
                child: Text('via $summary', style: KoraText.bodyMuted),
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
      borderRadius: KoraRadius.control,
      padding: const EdgeInsets.all(KoraSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            size: KoraSize.iconMd,
            color: KoraColors.primaryLight,
          ),
          const SizedBox(height: KoraSpacing.sm),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(value, style: KoraText.title),
          ),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(label, style: KoraText.caption, maxLines: 1),
          ),
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
        horizontal: KoraSpacing.md,
        vertical: KoraSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: KoraColors.primaryTint,
        borderRadius: BorderRadius.circular(KoraRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: KoraSize.iconSm,
            color: KoraColors.primaryLight,
          ),
          const SizedBox(width: KoraSpacing.xs),
          Text(
            text,
            style: KoraText.label.copyWith(
              color: KoraColors.primaryLight,
            ),
          ),
        ],
      ),
    );
  }
}
