import 'package:latlong2/latlong.dart';

/// Decodes a Google encoded polyline (precision 5), the format of
/// `map_route.polyline` (docs/contracts/interface.md §1). Throws
/// [FormatException] on a truncated string.
List<LatLng> decodePolyline(String encoded) {
  final points = <LatLng>[];
  var index = 0;
  var lat = 0;
  var lng = 0;

  int nextDelta() {
    var result = 0;
    var shift = 0;
    int byte;
    do {
      if (index >= encoded.length) {
        throw FormatException('Truncated polyline', encoded, index);
      }
      byte = encoded.codeUnitAt(index++) - 63;
      result |= (byte & 0x1f) << shift;
      shift += 5;
    } while (byte >= 0x20);
    return (result & 1) != 0 ? ~(result >> 1) : result >> 1;
  }

  while (index < encoded.length) {
    lat += nextDelta();
    lng += nextDelta();
    points.add(LatLng(lat / 1e5, lng / 1e5));
  }
  return points;
}
