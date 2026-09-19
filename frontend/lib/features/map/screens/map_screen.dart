import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/heading_provider.dart';
import '../../../providers/map_route_provider.dart';
import '../../../providers/map_style_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';
import '../data/location_source.dart';
import '../data/map_route.dart';
import '../widgets/map_chip.dart';
import '../widgets/map_markers.dart';
import '../widgets/openfreemap_layer.dart';
import '../widgets/route_card.dart';

/// The Map tab: OpenFreeMap tiles (flutter_map), the driver's live
/// position, and the route the co-rider draws from `map_route` events.
/// Navigation always renders here, never in an external maps app.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  /// Before the first location fix or route: downtown Austin, the demo's
  /// home area.
  static const fallbackCenter = LatLng(30.2672, -97.7431);

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final _map = MapController();
  bool _mapReady = false;

  /// The bottom route card. The camera keeps what it
  /// frames clear of it, and re-frames as the card grows or folds.
  final _sheetKey = GlobalKey();
  bool _reframeScheduled = false;

  /// What the camera does, from [mapFocusProvider]: follow the driver's
  /// live position, or keep the route framed. Either stops when the driver
  /// pans the map, until the next focus request.
  bool _following = true;
  bool _framingRoute = false;

  /// The stop the card shows, when the driver tapped a pin; otherwise the
  /// route's target.
  String? _selectedStopId;

  /// The driver's fold choice for the card; null follows the screen size.
  bool? _cardExpandedChoice;

  /// Short screens start the card folded so the route isn't hidden under it.
  bool get _cardExpanded =>
      _cardExpandedChoice ??
      MediaQuery.sizeOf(context).height >= KoraMap.compactHeight;

  @override
  void initState() {
    super.initState();
    ref.listenManual<MapRoute?>(mapRouteProvider, (_, route) {
      setState(() {
        _selectedStopId = null;
        _cardExpandedChoice = null;
      });
    });
    ref.listenManual<MapFocus>(mapFocusProvider, (_, focus) => _apply(focus));
    ref.listenManual<AsyncValue<LocationFix>>(locationProvider, (
      previous,
      next,
    ) {
      final fix = next.valueOrNull;
      if (fix == null) return;
      if (_following) {
        _moveTo(fix.point);
      } else if (_framingRoute && previous?.valueOrNull == null) {
        // The first fix after a route: frame the driver with it.
        _reframe();
      }
    });
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _onMapReady() {
    _mapReady = true;
    _apply(ref.read(mapFocusProvider));
  }

  void _apply(MapFocus focus) {
    _framingRoute =
        focus.target == MapFocusTarget.route &&
        ref.read(mapRouteProvider) != null;
    _following = !_framingRoute;
    _reframe();
  }

  /// Frames the route, or centres the driver's last fix.
  void _reframe() {
    if (!_mapReady) return;
    if (_framingRoute) {
      if (ref.read(mapRouteProvider) case final route?) _fitRoute(route);
    } else if (_following) {
      if (ref.read(locationProvider).valueOrNull case final fix?) {
        _moveTo(fix.point);
      }
    }
  }

  /// The sheet changed size mid-layout; re-frame once it has settled into
  /// this frame.
  bool _onSheetResized(SizeChangedLayoutNotification _) {
    if (!_reframeScheduled) {
      _reframeScheduled = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _reframeScheduled = false;
        if (mounted) _reframe();
      });
    }
    return true;
  }

  /// The map area left clear of the top controls and the bottom sheet.
  EdgeInsets _fitPadding() {
    final insets = MediaQuery.paddingOf(context);
    final height = MediaQuery.sizeOf(context).height;
    final top = insets.top + KoraMap.fitPadding + KoraSize.touchTarget;
    final sheet = _sheetKey.currentContext?.size?.height ?? height * 0.4;
    final bottom =
        insets.bottom + KoraSpacing.sm + sheet + KoraSpacing.lg;
    return EdgeInsets.fromLTRB(
      KoraMap.fitPadding,
      top,
      KoraMap.fitPadding,
      // A tall card on a small phone still leaves some map to fit into.
      math.min(bottom, height * (1 - KoraMap.minFitShare) - top),
    );
  }

  /// Fits the route and stop, plus the driver when they are near it. A far
  /// fix (the backend's mock data in another city than the phone) would
  /// zoom the fit out to a continent, so it is left out.
  void _fitRoute(MapRoute route) {
    final coordinates = route.coordinates;
    if (!_mapReady || coordinates.isEmpty) return;
    final fix = ref.read(locationProvider).valueOrNull;
    final target = route.target?.point;
    final includeDriver =
        fix != null &&
        target != null &&
        const Distance().distance(fix.point, target) <=
            KoraMap.maxFitDriverMetres;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [...coordinates, if (includeDriver) fix.point],
        padding: _fitPadding(),
        maxZoom: KoraMap.maxFitZoom,
      ),
    );
  }

  /// Centres [point] in the clear map area at the follow zoom.
  void _moveTo(LatLng point) {
    if (!_mapReady) return;
    _map.fitCamera(
      CameraFit.coordinates(
        coordinates: [point],
        padding: _fitPadding(),
        minZoom: KoraMap.followZoom,
        maxZoom: KoraMap.followZoom,
      ),
    );
  }

  /// Re-frames the route, or re-centres on (and follows) the driver.
  void _recenter() {
    final focus = ref.read(mapFocusProvider.notifier);
    if (ref.read(mapRouteProvider) != null) {
      focus.frameRoute();
    } else {
      focus.followDriver();
    }
  }

  @override
  Widget build(BuildContext context) {
    final route = ref.watch(mapRouteProvider);
    final location = ref.watch(locationProvider);
    final fix = location.valueOrNull;
    final heading = ref.watch(headingProvider).valueOrNull ?? fix?.heading;
    final vehicleMode = ref.watch(vehicleModeProvider);
    final mapStyle = ref.watch(mapStyleProvider);
    final insets = MediaQuery.paddingOf(context);

    RouteStop? shownStop = route?.target;
    if (route != null && _selectedStopId != null) {
      for (final stop in route.stops) {
        if (stop.deliveryId == _selectedStopId) shownStop = stop;
      }
    }

    return Stack(
      children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _map,
            options: MapOptions(
              initialCenter:
                  fix?.point ??
                  route?.target?.point ??
                  MapScreen.fallbackCenter,
              initialZoom: fix == null
                  ? KoraMap.initialZoom
                  : KoraMap.followZoom,
              backgroundColor: mapStyle.ground,
              // North stays up: easier to read at a glance on a bike mount.
              interactionOptions: const InteractionOptions(
                flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
              ),
              onMapReady: _onMapReady,
              onPositionChanged: (_, hasGesture) {
                if (!hasGesture) return;
                _following = false;
                _framingRoute = false;
              },
            ),
            children: [
              ref.watch(baseMapLayerProvider),
              if (route != null && route.line.length >= 2)
                PolylineLayer(
                  polylines: [
                    Polyline(
                      points: route.line,
                      strokeWidth: KoraMap.routeWidth,
                      color: KoraColors.primary,
                      borderStrokeWidth: KoraMap.routeCasingWidth,
                      borderColor: KoraColors.primaryDark,
                    ),
                  ],
                ),
              if (route != null)
                MarkerLayer(
                  markers: [
                    for (final stop in route.stops)
                      _stopMarker(stop, active: stop == shownStop),
                  ],
                ),
              if (fix != null)
                MarkerLayer(
                  markers: [
                    Marker(
                      point: fix.point,
                      width: KoraMap.positionHalo,
                      height: KoraMap.positionHalo,
                      child: PositionMarker(
                        heading: heading,
                        vehicleMode: vehicleMode,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ),
        // Keeps the status bar legible over bright tiles.
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: insets.top + KoraSpacing.xxl,
          child: const IgnorePointer(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [KoraColors.scrim, Colors.transparent],
                ),
              ),
            ),
          ),
        ),
        // Top row: the floating co-rider sits at the left (MascotOverlay),
        // so status chips start after it; recenter sits at the right.
        Positioned(
          top: insets.top + KoraSpacing.md,
          left:
              KoraSpacing.gutter +
              KoraSize.orbBubble +
              KoraSpacing.sm,
          right: KoraSpacing.gutter,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Align(
                  alignment: Alignment.topLeft,
                  child: _LocationStatus(location: location),
                ),
              ),
              const SizedBox(width: KoraSpacing.sm),
              _RoundGlassButton(
                icon: route != null
                    ? TablerIcons.arrowsMinimize
                    : TablerIcons.currentLocation,
                semanticLabel: route != null
                    ? 'Show the whole route'
                    : 'Center on my location',
                onTap: _recenter,
              ),
            ],
          ),
        ),
        Positioned(
          left: KoraSpacing.gutter,
          right: KoraSpacing.gutter,
          // Scaffold.extendBody puts the bottom nav's height in the padding.
          bottom: insets.bottom + KoraSpacing.sm,
          child: NotificationListener<SizeChangedLayoutNotification>(
            key: const Key('map-bottom-sheet'),
            onNotification: _onSheetResized,
            child: SizeChangedLayoutNotifier(
              child: Column(
                key: _sheetKey,
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  RouteCard(
                    route: route,
                    stop: shownStop,
                    expanded: _cardExpanded,
                    onToggle: () =>
                        setState(() => _cardExpandedChoice = !_cardExpanded),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Marker _stopMarker(RouteStop stop, {required bool active}) {
    final size = active ? KoraMap.stopPinActive : KoraMap.stopPin;
    final who = stop.recipientName ?? stop.address ?? 'Delivery stop';
    return Marker(
      key: ValueKey('stop-${stop.deliveryId}'),
      point: stop.point,
      width: size,
      height: size,
      child: StopPin(
        label: stop.sequence?.toString() ?? '',
        active: active,
        semanticLabel: stop.sequence == null
            ? who
            : 'Stop ${stop.sequence}, $who',
        onTap: () => setState(() {
          _selectedStopId = stop.deliveryId;
          _cardExpandedChoice = true;
        }),
      ),
    );
  }
}

/// Location loading / error states; nothing once a fix is in.
class _LocationStatus extends ConsumerWidget {
  const _LocationStatus({required this.location});
  final AsyncValue<LocationFix> location;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return location.when(
      data: (_) => const SizedBox.shrink(),
      loading: () => const MapChip(
        icon: TablerIcons.gps,
        message: 'Finding your location…',
      ),
      error: (error, _) {
        final problem = error is LocationUnavailable
            ? error.problem
            : LocationProblem.unavailable;
        final opensSettings =
            problem == LocationProblem.serviceOff ||
            problem == LocationProblem.deniedForever;
        // Onboarding asks for permission. This is the fallback for a driver
        // who skipped it there or revoked it since, and only a tap asks.
        final asks = problem == LocationProblem.denied;
        return MapChip(
          icon: TablerIcons.mapPinOff,
          tone: KoraColors.amber,
          message: error is LocationUnavailable
              ? error.message
              : const LocationUnavailable(LocationProblem.unavailable).message,
          actionLabel: opensSettings
              ? 'Settings'
              : asks
              ? 'Allow'
              : 'Try again',
          onAction: () async {
            final source = ref.read(locationSourceProvider);
            if (opensSettings) await source.openSettings(problem);
            if (asks) await source.requestPermission();
            ref.invalidate(locationProvider);
          },
        );
      },
    );
  }
}

class _RoundGlassButton extends StatelessWidget {
  const _RoundGlassButton({
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
  });

  final IconData icon;
  final String semanticLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: GlassCard(
          borderRadius: KoraRadius.pill,
          fill: KoraColors.raised.withValues(alpha: 0.88),
          child: SizedBox.square(
            dimension: KoraSize.touchTarget,
            child: Icon(
              icon,
              size: KoraSize.iconMd,
              color: KoraColors.textPrimary,
            ),
          ),
        ),
      ),
    );
  }
}
