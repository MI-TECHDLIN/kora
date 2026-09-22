import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/features/map/data/mercator.dart';

void main() {
  group('project', () {
    test('a point at the camera centre lands at the viewport centre', () {
      const center = LatLng(6.46, 3.39);
      final offset = MercatorProjection.project(
        center,
        center: center,
        zoom: 15,
        viewportSize: const Size(400, 800),
      );
      expect(offset.dx, closeTo(200, 0.001));
      expect(offset.dy, closeTo(400, 0.001));
    });

    test('east/north of centre lands right/above centre on screen', () {
      const center = LatLng(6.46, 3.39);
      final east = MercatorProjection.project(
        const LatLng(6.46, 3.40),
        center: center,
        zoom: 15,
        viewportSize: const Size(400, 800),
      );
      final north = MercatorProjection.project(
        const LatLng(6.47, 3.39),
        center: center,
        zoom: 15,
        viewportSize: const Size(400, 800),
      );
      expect(east.dx, greaterThan(200));
      expect(north.dy, lessThan(400));
    });

    test('uses MapLibre camera zoom scale', () {
      final offset = MercatorProjection.project(
        const LatLng(0, 90),
        center: const LatLng(0, 0),
        zoom: 0,
        viewportSize: const Size(400, 800),
      );
      // At zoom 0 MapLibre's world is 512 logical pixels wide, so a quarter
      // turn east is 128 pixels from the camera centre.
      expect(offset.dx, closeTo(328, 0.001));
      expect(offset.dy, closeTo(400, 0.001));
    });

    test('doubling the zoom doubles the pixel distance from centre', () {
      const center = LatLng(6.46, 3.39);
      const point = LatLng(6.46, 3.41);
      final atZ15 = MercatorProjection.project(
        point,
        center: center,
        zoom: 15,
        viewportSize: const Size(1000, 1000),
      );
      final atZ16 = MercatorProjection.project(
        point,
        center: center,
        zoom: 16,
        viewportSize: const Size(1000, 1000),
      );
      expect(atZ16.dx - 500, closeTo((atZ15.dx - 500) * 2, 0.01));
    });
  });

  group('shiftByPixels', () {
    test('is the inverse of project', () {
      const center = LatLng(30.2672, -97.7431);
      const point = LatLng(30.27, -97.74);
      const zoom = 14.0;
      const viewport = Size(390, 844);

      final onScreen = MercatorProjection.project(
        point,
        center: center,
        zoom: zoom,
        viewportSize: viewport,
      );
      final pixelsFromPoint = Offset(
        onScreen.dx - viewport.width / 2,
        onScreen.dy - viewport.height / 2,
      );
      final recovered = MercatorProjection.shiftByPixels(
        point,
        -pixelsFromPoint,
        zoom,
      );
      expect(recovered.latitude, closeTo(center.latitude, 1e-6));
      expect(recovered.longitude, closeTo(center.longitude, 1e-6));
    });

    test('a zero shift returns the same point', () {
      const point = LatLng(6.46, 3.39);
      final same = MercatorProjection.shiftByPixels(point, Offset.zero, 14);
      expect(same.latitude, closeTo(point.latitude, 1e-9));
      expect(same.longitude, closeTo(point.longitude, 1e-9));
    });
  });

  group('boundsOf', () {
    test('null for an empty list', () {
      expect(MercatorProjection.boundsOf(const []), isNull);
    });

    test('a single point is its own degenerate bounds', () {
      const point = LatLng(6.46, 3.39);
      final bounds = MercatorProjection.boundsOf([point]);
      expect(bounds!.southwest.latitude, point.latitude);
      expect(bounds.northeast.latitude, point.latitude);
      expect(bounds.southwest.longitude, point.longitude);
      expect(bounds.northeast.longitude, point.longitude);
    });

    test('the smallest box containing every point', () {
      final bounds = MercatorProjection.boundsOf(const [
        LatLng(6.46, 3.39),
        LatLng(6.47, 3.37),
        LatLng(6.44, 3.40),
      ]);
      expect(bounds!.southwest, const LatLng(6.44, 3.37));
      expect(bounds.northeast, const LatLng(6.47, 3.40));
    });
  });

  group('zoomToFit', () {
    test('a degenerate (single-point) box returns maxZoom', () {
      final bounds = MercatorProjection.boundsOf(const [LatLng(6.46, 3.39)])!;
      final zoom = MercatorProjection.zoomToFit(
        bounds,
        viewportSize: const Size(400, 800),
        paddingLeft: 20,
        paddingTop: 20,
        paddingRight: 20,
        paddingBottom: 20,
        maxZoom: 16,
      );
      expect(zoom, 16);
    });

    test('a wider box fits at a lower zoom than a narrower one', () {
      final narrow = MercatorProjection.boundsOf(const [
        LatLng(6.460, 3.390),
        LatLng(6.461, 3.391),
      ])!;
      final wide = MercatorProjection.boundsOf(const [
        LatLng(6.40, 3.30),
        LatLng(6.50, 3.45),
      ])!;
      final narrowZoom = MercatorProjection.zoomToFit(
        narrow,
        viewportSize: const Size(400, 800),
        paddingLeft: 20,
        paddingTop: 20,
        paddingRight: 20,
        paddingBottom: 20,
        maxZoom: 20,
      );
      final wideZoom = MercatorProjection.zoomToFit(
        wide,
        viewportSize: const Size(400, 800),
        paddingLeft: 20,
        paddingTop: 20,
        paddingRight: 20,
        paddingBottom: 20,
        maxZoom: 20,
      );
      expect(wideZoom, lessThan(narrowZoom));
    });

    test('never exceeds maxZoom even when padding leaves no room', () {
      final bounds = MercatorProjection.boundsOf(const [
        LatLng(6.46, 3.39),
        LatLng(6.47, 3.40),
      ])!;
      final zoom = MercatorProjection.zoomToFit(
        bounds,
        viewportSize: const Size(100, 100),
        paddingLeft: 60,
        paddingTop: 60,
        paddingRight: 60,
        paddingBottom: 60,
        maxZoom: 16,
      );
      expect(zoom, 16);
    });
  });
}
