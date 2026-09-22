import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

import 'package:latlong2/latlong.dart';

/// A geographic bounding box: the smallest rectangle containing a set of
/// points. Kora's own type, not maplibre_gl's `LatLngBounds` -- this file
/// stays free of any MapLibre dependency (see [MercatorProjection]), and its
/// two callers (`kora_map_controller.dart`, `map_screen.dart`) convert to
/// maplibre_gl types at the point they actually call into the plugin.
class GeoBounds {
  const GeoBounds({required this.southwest, required this.northeast});
  final LatLng southwest;
  final LatLng northeast;
}

/// Spherical Web Mercator (EPSG:3857) tile math: the projection every
/// slippy-map renderer uses (OSM, Mapbox, MapLibre, Google). Kora locks the
/// map north-up (`rotateGesturesEnabled: false` on the `MapLibreMap` in
/// map_screen.dart), so these formulas skip bearing and tilt entirely.
///
/// MapLibre Native renders the camera on the platform side, invisible to
/// Flutter's widget tree. This is Kora's own projection, standing in for
/// that native camera in two places: placing the screen-space marker
/// overlays over the native map surface (map_markers.dart's callers in
/// map_screen.dart), and computing the padding-aware camera targets
/// MapLibre's `CameraUpdate` API doesn't offer directly (`_MapScreenState`).
class MercatorProjection {
  const MercatorProjection._();

  /// Total map width/height in pixels at [zoom], per the 256px tile grid
  /// every OSM-derived renderer (and MapLibre) uses.
  static double _worldSize(double zoom) => 256 * math.pow(2, zoom).toDouble();

  static Offset _worldPixel(LatLng point, double zoom) {
    final scale = _worldSize(zoom);
    final x = (point.longitude + 180) / 360 * scale;
    final sinLat = math.sin(
      point.latitude * math.pi / 180,
    ).clamp(-0.9999, 0.9999);
    final y =
        (0.5 - math.log((1 + sinLat) / (1 - sinLat)) / (4 * math.pi)) * scale;
    return Offset(x, y);
  }

  static LatLng _fromWorldPixel(Offset pixel, double zoom) {
    final scale = _worldSize(zoom);
    final lng = pixel.dx / scale * 360 - 180;
    final n = math.pi - 2 * math.pi * pixel.dy / scale;
    final lat = 180 / math.pi * math.atan(0.5 * (math.exp(n) - math.exp(-n)));
    return LatLng(lat, lng);
  }

  /// [point]'s pixel position in a viewport of [viewportSize] whose centre
  /// shows [center] at [zoom]. Places a marker overlay over the native map.
  static Offset project(
    LatLng point, {
    required LatLng center,
    required double zoom,
    required Size viewportSize,
  }) {
    final delta = _worldPixel(point, zoom) - _worldPixel(center, zoom);
    return Offset(viewportSize.width / 2, viewportSize.height / 2) + delta;
  }

  /// The point that renders [pixels] away from [point]'s own screen
  /// position, at [zoom]. The inverse of [project]: computes a camera
  /// centre that puts [point] somewhere other than the viewport's true
  /// centre (see `_MapScreenState._moveTo`, which centres the driver inside
  /// the padded, card-clear area instead of the full screen).
  static LatLng shiftByPixels(LatLng point, Offset pixels, double zoom) {
    return _fromWorldPixel(_worldPixel(point, zoom) + pixels, zoom);
  }

  /// The greatest zoom, capped at [maxZoom], at which [bounds] still fits
  /// inside a viewport of [viewportSize] once the padding on each side is
  /// subtracted. Replaces flutter_map's `CameraFit.coordinates(padding:,
  /// maxZoom:)`: MapLibre's `CameraUpdate.newLatLngBounds` fits bounds to
  /// padding too, but always at "the greatest possible zoom level", with no
  /// [maxZoom] cap of its own -- close-together stops would zoom in far
  /// past what `_fitRoute` wants. A degenerate (zero-area, e.g.
  /// single-point) box has no span to fit, so it returns [maxZoom].
  static double zoomToFit(
    GeoBounds bounds, {
    required Size viewportSize,
    required double paddingLeft,
    required double paddingTop,
    required double paddingRight,
    required double paddingBottom,
    required double maxZoom,
    double minZoom = 0,
  }) {
    final availableWidth = viewportSize.width - paddingLeft - paddingRight;
    final availableHeight = viewportSize.height - paddingTop - paddingBottom;
    if (availableWidth <= 0 || availableHeight <= 0) return maxZoom;

    // A world-pixel span at zoom 0, scaled by 2^zoom at any other zoom (the
    // same [_worldSize] factor [_worldPixel] applies), so this ratio holds
    // at every zoom level, not just 0.
    final sw = _worldPixel(bounds.southwest, 0);
    final ne = _worldPixel(bounds.northeast, 0);
    final spanX = (ne.dx - sw.dx).abs();
    final spanY = (sw.dy - ne.dy).abs();

    var zoom = maxZoom;
    if (spanX > 0) {
      zoom = math.min(zoom, math.log(availableWidth / spanX) / math.ln2);
    }
    if (spanY > 0) {
      zoom = math.min(zoom, math.log(availableHeight / spanY) / math.ln2);
    }
    return zoom.clamp(minZoom, maxZoom);
  }

  /// The smallest bounds containing every point, or null for an empty list.
  static GeoBounds? boundsOf(Iterable<LatLng> points) {
    double? west, east, south, north;
    for (final point in points) {
      west = west == null ? point.longitude : math.min(west, point.longitude);
      east = east == null ? point.longitude : math.max(east, point.longitude);
      south = south == null ? point.latitude : math.min(south, point.latitude);
      north = north == null ? point.latitude : math.max(north, point.latitude);
    }
    if (west == null) return null;
    return GeoBounds(
      southwest: LatLng(south!, west),
      northeast: LatLng(north!, east!),
    );
  }
}
