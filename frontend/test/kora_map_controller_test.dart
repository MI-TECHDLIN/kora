import 'package:flutter_test/flutter_test.dart';
import 'package:latlong2/latlong.dart';
import 'package:voiceops/features/map/data/kora_map_controller.dart';

void main() {
  group('routeGeometryAtProgress', () {
    const route = [
      LatLng(0, 0),
      LatLng(0, 1),
      LatLng(0, 3),
    ];

    test('starts as a collapsed MapLibre-compatible line', () {
      expect(routeGeometryAtProgress(route, 0), [route.first, route.first]);
    });

    test('interpolates by distance rather than coordinate count', () {
      final halfway = routeGeometryAtProgress(route, 0.5);
      expect(halfway, hasLength(3));
      expect(halfway[0], route[0]);
      expect(halfway[1], route[1]);
      expect(halfway[2].latitude, 0);
      expect(halfway[2].longitude, closeTo(1.5, 0.001));
    });

    test('clamps progress and preserves the complete route at the end', () {
      expect(routeGeometryAtProgress(route, -1), [route.first, route.first]);
      expect(routeGeometryAtProgress(route, 2), route);
    });
  });
}
