import 'dart:math' as math;

import 'package:flutter/scheduler.dart';
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

  /// Starts a camera move with an explicit native animation [duration].
  Future<void> animateCamera(
    CameraUpdate update, {
    required Duration duration,
  });

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
  Future<void>? _lineCreation;
  int _routeRevision = 0;

  @override
  CameraPosition? get cameraPosition => _controller.cameraPosition;

  @override
  Future<void> animateCamera(
    CameraUpdate update, {
    required Duration duration,
  }) async {
    await _controller.animateCamera(update, duration: duration);
  }

  @override
  Future<void> setRouteLine(List<LatLng> coordinates) async {
    final revision = ++_routeRevision;
    if (coordinates.length < 2) {
      await _clear();
      return;
    }

    // Start with a zero-length line, then reveal equal shares of the route's
    // physical length each frame. Basing progress on distance rather than
    // coordinate count keeps sparse and dense OSRM geometries moving at the
    // same perceived pace.
    await _setGeometry(routeGeometryAtProgress(coordinates, 0));
    final stopwatch = Stopwatch()..start();
    while (revision == _routeRevision) {
      await SchedulerBinding.instance.endOfFrame;
      if (revision != _routeRevision) return;
      final elapsed = stopwatch.elapsedMilliseconds;
      final rawProgress = math.min(
        1.0,
        elapsed / KoraMotion.routeReveal.inMilliseconds,
      ).toDouble();
      final progress = KoraMotion.standard.transform(rawProgress);
      await _setGeometry(routeGeometryAtProgress(coordinates, progress));
      if (rawProgress == 1) return;
    }
  }

  Future<void> _setGeometry(List<LatLng> coordinates) async {
    final geometry = coordinates.map(toMaplibreLatLng).toList();
    final lineCreation = _lineCreation;
    if (lineCreation != null) {
      await lineCreation;
      await _setGeometry(coordinates);
      return;
    }
    final casing = _casing;
    final line = _line;
    if (casing == null || line == null) {
      final creation = _addLinePair(geometry);
      _lineCreation = creation;
      try {
        await creation;
      } finally {
        if (identical(_lineCreation, creation)) _lineCreation = null;
      }
    } else {
      await Future.wait([
        _controller.updateLine(casing, LineOptions(geometry: geometry)),
        _controller.updateLine(line, LineOptions(geometry: geometry)),
      ]);
    }
  }

  Future<void> _addLinePair(List<maplibre.LatLng> geometry) async {
    // The line manager draws later adds on top, so the wider, darker casing
    // goes down first and the primary stroke goes on top of it.
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
  }

  Future<void> _clear() async {
    final lineCreation = _lineCreation;
    if (lineCreation != null) await lineCreation;
    final casing = _casing;
    final line = _line;
    if (line == null || casing == null) return;
    _casing = null;
    _line = null;
    await _controller.removeLine(line);
    await _controller.removeLine(casing);
  }
}

/// The visible prefix of [coordinates] at [progress], measured by route
/// distance. The last point is interpolated within its segment so even a
/// two-coordinate route draws smoothly instead of advancing vertex by vertex.
List<LatLng> routeGeometryAtProgress(
  List<LatLng> coordinates,
  double progress,
) {
  if (coordinates.length < 2) return List.of(coordinates);
  final clamped = progress.clamp(0.0, 1.0).toDouble();
  if (clamped >= 1) return List.of(coordinates);

  const distance = Distance();
  final lengths = <double>[];
  var total = 0.0;
  for (var index = 1; index < coordinates.length; index++) {
    final length = distance.distance(
      coordinates[index - 1],
      coordinates[index],
    );
    lengths.add(length);
    total += length;
  }
  if (total == 0) return List.of(coordinates);

  final target = total * clamped;
  var travelled = 0.0;
  final visible = <LatLng>[coordinates.first];
  for (var index = 1; index < coordinates.length; index++) {
    final segmentLength = lengths[index - 1];
    final nextTravelled = travelled + segmentLength;
    if (nextTravelled <= target) {
      visible.add(coordinates[index]);
      travelled = nextTravelled;
      continue;
    }

    final start = coordinates[index - 1];
    final end = coordinates[index];
    final segmentProgress = segmentLength == 0
        ? 0.0
        : (target - travelled) / segmentLength;
    visible.add(
      LatLng(
        start.latitude +
            (end.latitude - start.latitude) * segmentProgress,
        start.longitude +
            (end.longitude - start.longitude) * segmentProgress,
      ),
    );
    break;
  }

  // MapLibre line annotations require at least two coordinates. At zero
  // progress, a duplicated first point renders as the intended collapsed line.
  if (visible.length == 1) visible.add(visible.first);
  return visible;
}
