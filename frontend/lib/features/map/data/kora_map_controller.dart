import 'package:latlong2/latlong.dart';
import 'package:maplibre_gl/maplibre_gl.dart' hide LatLng, LatLngBounds;
import 'package:maplibre_gl/maplibre_gl.dart' as maplibre show LatLng;

import '../../../core/theme/tokens.dart';

/// Converts latlong2's `LatLng` (Kora's own point type, used throughout
/// map_route.dart and location_source.dart) to maplibre_gl's own,
/// differently-defined `LatLng`, which every maplibre_gl call in this file
/// and its callers (openfreemap_layer.dart, map_screen.dart) needs instead.
maplibre.LatLng toMaplibreLatLng(LatLng point) =>
    maplibre.LatLng(point.latitude, point.longitude);

/// What the Map tab needs from the map engine: camera control and the
/// road-route line. A thin seam over [MapLibreMapController] so
/// map_screen.dart's follow/frame-route logic can be driven in tests without
/// a real platform view. `MapLibreMap` mounts a native platform view over a
/// method channel; plain `flutter_test` has no engine on the other end of
/// it. See test/fake_map_controller.dart.
abstract class KoraMapController {
  /// The most recent camera position reported by the platform side. Null
  /// until the first `onCameraMove`.
  CameraPosition? get cameraPosition;

  /// Moves the camera. Completes once the platform side settles.
  Future<void> animateCamera(CameraUpdate update);

  /// Adds or replaces the road-route line, drawn as a casing under a
  /// narrower primary stroke (`KoraMap.routeCasingWidth`/`routeWidth`).
  /// Pass fewer than two coordinates to clear it.
  Future<void> setRouteLine(List<LatLng> coordinates);
}

/// The real [KoraMapController], wrapping a live [MapLibreMapController].
class MapLibreKoraMapController implements KoraMapController {
  MapLibreKoraMapController(this._controller);

  final MapLibreMapController _controller;
  Line? _casing;
  Line? _line;

  @override
  CameraPosition? get cameraPosition => _controller.cameraPosition;

  @override
  Future<void> animateCamera(CameraUpdate update) async {
    await _controller.animateCamera(update);
  }

  @override
  Future<void> setRouteLine(List<LatLng> coordinates) async {
    if (coordinates.length < 2) {
      await _clear();
      return;
    }
    final geometry = coordinates.map(toMaplibreLatLng).toList();
    final casing = _casing;
    final line = _line;
    if (casing == null || line == null) {
      // The line manager draws later adds on top, so the wider, darker
      // casing goes down first and the primary stroke goes on top of it.
      _casing = await _controller.addLine(
        LineOptions(
          geometry: geometry,
          lineColor: KoraColors.primaryDark.toHexStringRGB(),
          lineWidth: KoraMap.routeWidth + KoraMap.routeCasingWidth * 2,
        ),
      );
      _line = await _controller.addLine(
        LineOptions(
          geometry: geometry,
          lineColor: KoraColors.primary.toHexStringRGB(),
          lineWidth: KoraMap.routeWidth,
        ),
      );
    } else {
      await _controller.updateLine(casing, LineOptions(geometry: geometry));
      await _controller.updateLine(line, LineOptions(geometry: geometry));
    }
  }

  Future<void> _clear() async {
    final casing = _casing;
    final line = _line;
    if (line == null || casing == null) return;
    _casing = null;
    _line = null;
    await _controller.removeLine(line);
    await _controller.removeLine(casing);
  }
}
