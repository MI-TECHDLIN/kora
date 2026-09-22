import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' show CameraPosition, CameraUpdate;
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../core/widgets/glass_card.dart';
import '../../../providers/location_provider.dart';
import '../../../providers/heading_provider.dart';
import '../../../providers/map_route_provider.dart';
import '../../../providers/map_style_provider.dart';
import '../../../providers/vehicle_mode_provider.dart';
import '../data/kora_map_controller.dart';
import '../data/location_source.dart';
import '../data/map_route.dart';
import '../data/mercator.dart';
import '../widgets/map_chip.dart';
import '../widgets/map_markers.dart';
import '../widgets/openfreemap_layer.dart';
import '../widgets/route_card.dart';

/// The Map tab: OpenFreeMap tiles rendered by MapLibre Native, the driver's
/// live position, and the route the co-rider draws from `map_route` events.
/// Navigation always renders here, never in an external maps app.
///
/// MapLibre renders the camera and base tiles on the platform side, outside
/// Flutter's widget tree, so this screen owns two things flutter_map used to
/// give it for free: the padding-aware camera math (see mercator.dart) and
/// the stop/position pins, drawn as ordinary [Positioned] widgets projected
/// onto the native camera every [_onCameraMove] tick rather than as
/// platform-rendered symbols. That keeps `StopPin`'s active/inactive
/// transition and `PositionMarker`'s heading rotation exactly as they were
/// (both are just Flutter widgets); the alternative -- pre-rendered image
/// markers via `addImage`/`iconImage` -- would trade that smooth
/// AnimatedContainer crossfade for a hard cut between two baked icons.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  /// Before the first location fix or route: downtown Austin, the demo's
  /// home area.
  static const fallbackCenter = LatLng(30.2672, -97.7431);

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  KoraMapController? _controller;
  bool _mapReady = false;
  bool _styleLoaded = false;

  /// The most recent camera position, from [_onCameraMove]. Seeded with the
  /// map's initial camera in [_onMapCreated] so markers never render at a
  /// stale spot before the first move event arrives.
  CameraPosition? _camera;

  /// True while a camera move was requested by this screen (`_moveTo`,
  /// `_fitRoute`), so [_onCameraMove] can tell it apart from a driver's
  /// gesture. MapLibre's `onCameraMove` fires for both alike, unlike
  /// flutter_map's `onPositionChanged(position, hasGesture)`.
  bool _programmaticMove = false;

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
      unawaited(_syncRouteLine(route));
    });
    ref.listenManual<MapFocus>(mapFocusProvider, (_, focus) => _apply(focus));
    ref.listenManual<AsyncValue<LocationFix>>(locationProvider, (
      previous,
      next,
    ) {
      final fix = next.valueOrNull;
      if (fix == null) return;
      if (_following) {
        unawaited(_moveTo(fix.point));
      } else if (_framingRoute && previous?.valueOrNull == null) {
        // The first fix after a route: frame the driver with it.
        _reframe();
      }
    });
  }

  void _onMapCreated(KoraMapController controller) {
    _controller = controller;
    _mapReady = true;
    // A style switch creates a fresh native controller. Do not send route
    // annotations to it until that controller reports its style ready.
    _styleLoaded = false;
    _apply(ref.read(mapFocusProvider));
  }

  void _onStyleLoaded() {
    _styleLoaded = true;
    unawaited(_syncRouteLine(ref.read(mapRouteProvider)));
  }

  void _onCameraMove(CameraPosition position) {
    setState(() => _camera = position);
    if (!_programmaticMove) {
      _following = false;
      _framingRoute = false;
    }
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
      if (ref.read(mapRouteProvider) case final route?)
        unawaited(_fitRoute(route));
    } else if (_following) {
      if (ref.read(locationProvider).valueOrNull case final fix?) {
        unawaited(_moveTo(fix.point));
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
    final bottom = insets.bottom + KoraSpacing.sm + sheet + KoraSpacing.lg;
    return EdgeInsets.fromLTRB(
      KoraMap.fitPadding,
      top,
      KoraMap.fitPadding,
      // A tall card on a small phone still leaves some map to fit into.
      math.min(bottom, height * (1 - KoraMap.minFitShare) - top),
    );
  }

  /// Moves the camera so [point] sits at the centre of the clear map area
  /// (inset by [_fitPadding]) rather than the full screen, at [zoom].
  /// MapLibre's `CameraUpdate` has no "pad the visible area" primitive of
  /// its own (unlike flutter_map's `CameraFit`), so the padding's
  /// left/right and top/bottom asymmetry is converted into a pixel offset
  /// and applied to [point] before it becomes the camera's true centre; see
  /// mercator.dart.
  Future<void> _centerInClearArea(LatLng point, {required double zoom}) async {
    final controller = _controller;
    if (controller == null) return;
    final padding = _fitPadding();
    final dx = (padding.left - padding.right) / 2;
    final dy = (padding.top - padding.bottom) / 2;
    final target = (dx == 0 && dy == 0)
        ? point
        : MercatorProjection.shiftByPixels(point, Offset(-dx, -dy), zoom);
    _programmaticMove = true;
    try {
      await controller.animateCamera(
        CameraUpdate.newLatLngZoom(toMaplibreLatLng(target), zoom),
      );
    } finally {
      _programmaticMove = false;
    }
  }

  /// Fits the route and stop, plus the driver when they are near it. A far
  /// fix (the backend's mock data in another city than the phone) would
  /// zoom the fit out to a continent, so it is left out.
  Future<void> _fitRoute(MapRoute route) async {
    if (!_mapReady) return;
    final coordinates = route.coordinates;
    if (coordinates.isEmpty) return;
    final fix = ref.read(locationProvider).valueOrNull;
    final target = route.target?.point;
    final includeDriver =
        fix != null &&
        target != null &&
        const Distance().distance(fix.point, target) <=
            KoraMap.maxFitDriverMetres;
    final points = [...coordinates, if (includeDriver) fix.point];
    final bounds = MercatorProjection.boundsOf(points);
    if (bounds == null) return;

    final padding = _fitPadding();
    final zoom = MercatorProjection.zoomToFit(
      bounds,
      viewportSize: MediaQuery.sizeOf(context),
      paddingLeft: padding.left,
      paddingTop: padding.top,
      paddingRight: padding.right,
      paddingBottom: padding.bottom,
      maxZoom: KoraMap.maxFitZoom,
    );
    final center = LatLng(
      (bounds.southwest.latitude + bounds.northeast.latitude) / 2,
      (bounds.southwest.longitude + bounds.northeast.longitude) / 2,
    );
    await _centerInClearArea(center, zoom: zoom);
  }

  /// Centres [point] in the clear map area at the follow zoom.
  Future<void> _moveTo(LatLng point) async {
    if (!_mapReady) return;
    await _centerInClearArea(point, zoom: KoraMap.followZoom);
  }

  Future<void> _syncRouteLine(MapRoute? route) async {
    final controller = _controller;
    if (controller == null || !_styleLoaded) return;
    await controller.setRouteLine(route?.line ?? const []);
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

    final initialCenter =
        fix?.point ?? route?.target?.point ?? MapScreen.fallbackCenter;
    final initialZoom = fix == null ? KoraMap.initialZoom : KoraMap.followZoom;

    return Stack(
      children: [
        Positioned.fill(
          child: ref.watch(koraMapViewBuilderProvider)(
            style: mapStyle,
            initialCenter: initialCenter,
            initialZoom: initialZoom,
            onMapCreated: (controller) {
              _camera = CameraPosition(
                target: toMaplibreLatLng(initialCenter),
                zoom: initialZoom,
              );
              _onMapCreated(controller);
            },
            onStyleLoaded: _onStyleLoaded,
            onCameraMove: _onCameraMove,
          ),
        ),
        ..._overlayMarkers(
          route: route,
          shownStop: shownStop,
          fix: fix,
          heading: heading,
          vehicleMode: vehicleMode,
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
          left: KoraSpacing.gutter + KoraSize.orbBubble + KoraSpacing.sm,
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

  /// Stop pins and the position marker, as [Positioned] widgets projected
  /// onto the native camera (see mercator.dart). Empty before the first
  /// camera position is known.
  List<Widget> _overlayMarkers({
    required MapRoute? route,
    required RouteStop? shownStop,
    required LocationFix? fix,
    required double? heading,
    required VehicleMode vehicleMode,
  }) {
    final camera = _camera;
    if (camera == null) return const [];
    final size = MediaQuery.sizeOf(context);

    final center = LatLng(camera.target.latitude, camera.target.longitude);
    Offset project(LatLng point) => MercatorProjection.project(
      point,
      center: center,
      zoom: camera.zoom,
      viewportSize: size,
    );

    final markers = <Widget>[];
    if (route != null) {
      for (final stop in route.stops) {
        final active = stop == shownStop;
        final dim = active ? KoraMap.stopPinActive : KoraMap.stopPin;
        final who = stop.recipientName ?? stop.address ?? 'Delivery stop';
        final pos = project(stop.point);
        markers.add(
          Positioned(
            key: ValueKey('stop-${stop.deliveryId}'),
            left: pos.dx - dim / 2,
            top: pos.dy - dim / 2,
            width: dim,
            height: dim,
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
          ),
        );
      }
    }
    if (fix != null) {
      final pos = project(fix.point);
      markers.add(
        Positioned(
          left: pos.dx - KoraMap.positionHalo / 2,
          top: pos.dy - KoraMap.positionHalo / 2,
          width: KoraMap.positionHalo,
          height: KoraMap.positionHalo,
          child: IgnorePointer(
            child: PositionMarker(heading: heading, vehicleMode: vehicleMode),
          ),
        ),
      );
    }
    return markers;
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
