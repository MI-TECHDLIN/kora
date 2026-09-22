import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' hide LatLng, LatLngBounds;
import 'package:tabler_icons_plus/tabler_icons_plus.dart';

import '../../../core/theme/tokens.dart';
import '../../../providers/map_style_provider.dart';
import '../data/kora_map_controller.dart';
import 'map_chip.dart';

/// How long the style has to finish loading before the map surface offers a
/// Retry. MapLibre has no public "style failed to load" callback (unlike
/// vector_map_tiles' old Future-based loader, whose rejection drove the
/// error chip directly), so a stall is detected by timeout instead.
const koraMapStyleLoadTimeout = Duration(seconds: 10);

/// Fired once the map engine hands back a controller. The controller is
/// wrapped in [KoraMapController], the seam map_screen.dart programs
/// against, so tests can drive its camera/route-line logic without a real
/// platform view.
typedef KoraMapCreatedCallback = void Function(KoraMapController controller);

/// Builds the widget that shows the map surface. A provider (not a plain
/// widget constant) because map_screen.dart must reach the controller
/// [onMapCreated] hands back and hear every camera move via [onCameraMove];
/// a declarative child layer, as flutter_map's `OpenFreeMapLayer` used to
/// be, can't offer either. Tests override this to stand in a widget that
/// never touches the platform channel; see test/fake_map_controller.dart.
typedef KoraMapViewBuilder =
    Widget Function({
      required MapStyle style,
      required LatLng initialCenter,
      required double initialZoom,
      required KoraMapCreatedCallback onMapCreated,
      required VoidCallback onStyleLoaded,
      required ValueChanged<CameraPosition> onCameraMove,
    });

final koraMapViewBuilderProvider = Provider<KoraMapViewBuilder>(
  (ref) => buildMapLibreView,
);

/// The driver's chosen OpenFreeMap style as a `MapLibreMap`, over the
/// style's own ground colour. A branded skeleton in the same palette shows
/// while the style loads; if it stalls, a chip offers a real retry.
Widget buildMapLibreView({
  required MapStyle style,
  required LatLng initialCenter,
  required double initialZoom,
  required KoraMapCreatedCallback onMapCreated,
  required VoidCallback onStyleLoaded,
  required ValueChanged<CameraPosition> onCameraMove,
}) {
  return _KoraMapLibreView(
    style: style,
    initialCenter: initialCenter,
    initialZoom: initialZoom,
    onMapCreated: onMapCreated,
    onStyleLoaded: onStyleLoaded,
    onCameraMove: onCameraMove,
  );
}

class _KoraMapLibreView extends StatefulWidget {
  const _KoraMapLibreView({
    required this.style,
    required this.initialCenter,
    required this.initialZoom,
    required this.onMapCreated,
    required this.onStyleLoaded,
    required this.onCameraMove,
  });

  final MapStyle style;
  final LatLng initialCenter;
  final double initialZoom;
  final KoraMapCreatedCallback onMapCreated;
  final VoidCallback onStyleLoaded;
  final ValueChanged<CameraPosition> onCameraMove;

  @override
  State<_KoraMapLibreView> createState() => _KoraMapLibreViewState();
}

class _KoraMapLibreViewState extends State<_KoraMapLibreView> {
  bool _styleLoaded = false;
  bool _timedOut = false;
  int _attempt = 0;
  Timer? _timeoutTimer;
  MapLibreMapController? _controller;
  CameraPosition? _lastCameraPosition;

  @override
  void initState() {
    super.initState();
    _armTimeout();
  }

  @override
  void didUpdateWidget(covariant _KoraMapLibreView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.style != widget.style) {
      // A new style: nothing rendered for the previous one (tiles, sprites)
      // survives a switch, matching the old VectorTileLayer's per-style key.
      _styleLoaded = false;
      _timedOut = false;
      _armTimeout();
    }
  }

  @override
  void dispose() {
    _timeoutTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onMapCreated(MapLibreMapController controller) {
    _controller?.removeListener(_onControllerChanged);
    _controller = controller;
    _lastCameraPosition = controller.cameraPosition;
    controller.addListener(_onControllerChanged);
    widget.onMapCreated(MapLibreKoraMapController(controller));
  }

  void _onControllerChanged() {
    final position = _controller?.cameraPosition;
    if (position == null || position == _lastCameraPosition) return;
    _lastCameraPosition = position;
    widget.onCameraMove(position);
  }

  void _armTimeout() {
    _timeoutTimer?.cancel();
    _timeoutTimer = Timer(koraMapStyleLoadTimeout, () {
      if (mounted && !_styleLoaded) setState(() => _timedOut = true);
    });
  }

  void _retry() {
    setState(() {
      _attempt++;
      _styleLoaded = false;
      _timedOut = false;
    });
    _armTimeout();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        ColoredBox(key: const Key('map-ground'), color: widget.style.ground),
        MapLibreMap(
          key: ValueKey('${widget.style}-$_attempt'),
          styleString: widget.style.url,
          initialCameraPosition: CameraPosition(
            target: toMaplibreLatLng(widget.initialCenter),
            zoom: widget.initialZoom,
          ),
          trackCameraPosition: true,
          compassEnabled: false,
          myLocationEnabled: false,
          // North stays up: easier to read at a glance on a bike mount.
          // flutter_map never had tilt either, so both stay off to keep the
          // gesture feel unchanged.
          rotateGesturesEnabled: false,
          tiltGesturesEnabled: false,
          onMapCreated: _onMapCreated,
          onStyleLoadedCallback: () {
            _timeoutTimer?.cancel();
            if (mounted) setState(() => _styleLoaded = true);
            widget.onStyleLoaded();
          },
        ),
        if (!_styleLoaded && !_timedOut)
          MapLoadingSkeleton(style: widget.style),
        if (_timedOut)
          Align(
            alignment: Alignment.center,
            child: Padding(
              padding: const EdgeInsets.all(KoraSpacing.gutter),
              child: MapChip(
                icon: TablerIcons.map2,
                message: "The map didn't load. Your route still works.",
                actionLabel: 'Retry',
                onAction: _retry,
              ),
            ),
          ),
      ],
    );
  }
}

/// A quiet street-grid placeholder in the chosen map style's palette, instead
/// of a blank canvas or bare spinner. Only while the style loads: under live
/// tiles, a static fake street grid would show through as a second map.
class MapLoadingSkeleton extends StatelessWidget {
  const MapLoadingSkeleton({super.key, required this.style});

  final MapStyle style;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Map loading',
      child: ExcludeSemantics(
        child: ColoredBox(
          key: const Key('map-loading-skeleton'),
          color: style.ground,
          child: CustomPaint(painter: _StreetGridPainter(dark: style.isDark)),
        ),
      ),
    );
  }
}

class _StreetGridPainter extends CustomPainter {
  const _StreetGridPainter({required this.dark});

  final bool dark;

  @override
  void paint(Canvas canvas, Size size) {
    final minor = Paint()
      ..color = dark ? KoraColors.divider : KoraColors.mapSkeletonLightRoad
      ..strokeWidth = KoraMap.skeletonRoadWidth
      ..style = PaintingStyle.stroke;
    final major = Paint()
      ..color = KoraColors.primaryTint
      ..strokeWidth = KoraMap.skeletonMainRoadWidth
      ..style = PaintingStyle.stroke;
    final buildings = Paint()
      ..color = dark ? KoraColors.elevated : KoraColors.mapSkeletonLightBlock
      ..style = PaintingStyle.fill;

    for (final rect in <Rect>[
      Rect.fromLTWH(
        size.width * .08,
        size.height * .12,
        size.width * .22,
        size.height * .13,
      ),
      Rect.fromLTWH(
        size.width * .62,
        size.height * .08,
        size.width * .27,
        size.height * .18,
      ),
      Rect.fromLTWH(
        size.width * .15,
        size.height * .56,
        size.width * .3,
        size.height * .16,
      ),
      Rect.fromLTWH(
        size.width * .67,
        size.height * .63,
        size.width * .2,
        size.height * .12,
      ),
    ]) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          rect,
          const Radius.circular(KoraRadius.control),
        ),
        buildings,
      );
    }
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), major);
    canvas.drawLine(
      Offset(0, size.height * .72),
      Offset(size.width, size.height * .3),
      minor,
    );
    canvas.drawLine(
      Offset(size.width * .45, 0),
      Offset(size.width * .2, size.height),
      minor,
    );
    canvas.drawLine(
      Offset(size.width * .82, 0),
      Offset(size.width * .55, size.height),
      minor,
    );
  }

  @override
  bool shouldRepaint(covariant _StreetGridPainter oldDelegate) =>
      oldDelegate.dark != dark;
}
