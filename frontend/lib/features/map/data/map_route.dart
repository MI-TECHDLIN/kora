import 'package:latlong2/latlong.dart';

import 'polyline_codec.dart';

/// One delivery stop on a `map_route` event.
class RouteStop {
  const RouteStop({
    required this.deliveryId,
    required this.point,
    this.sequence,
    this.recipientName,
    this.address,
  });

  final String deliveryId;
  final LatLng point;
  final int? sequence;
  final String? recipientName;
  final String? address;
}

/// The route the co-rider asked the map to draw: the `map_route` event
/// (docs/contracts/interface.md §1), with the polyline already decoded.
class MapRoute {
  const MapRoute({
    required this.deliveryId,
    required this.stops,
    required this.path,
    this.summary,
    this.distanceKm,
    this.durationMins,
    this.durationText,
  });

  /// Parses the event body. Stops without coordinates can't be pinned and
  /// are dropped. When Directions found no road route the backend sends
  /// `polyline: ""` and null trip stats: [path] is empty, so the map pins
  /// the stop and draws no line. A malformed polyline is treated the same.
  factory MapRoute.fromJson(Map<String, dynamic> json) {
    final stops = <RouteStop>[
      for (final stop in json['stops'] as List? ?? const [])
        if (stop case {'latitude': final num lat, 'longitude': final num lng})
          RouteStop(
            deliveryId: '${stop['delivery_id'] ?? ''}',
            point: LatLng(lat.toDouble(), lng.toDouble()),
            sequence: (stop['sequence'] as num?)?.toInt(),
            recipientName: stop['recipient_name'] as String?,
            address: stop['address'] as String?,
          ),
    ];
    var path = const <LatLng>[];
    if (json['polyline'] case final String encoded when encoded.isNotEmpty) {
      try {
        path = decodePolyline(encoded);
      } on FormatException {
        path = const [];
      }
    }
    return MapRoute(
      deliveryId: '${json['delivery_id'] ?? ''}',
      stops: stops,
      path: path,
      summary: json['summary'] as String?,
      distanceKm: (json['distance_km'] as num?)?.toDouble(),
      durationMins: (json['duration_mins'] as num?)?.toInt(),
      durationText: json['duration_text'] as String?,
    );
  }

  final String deliveryId;
  final List<RouteStop> stops;
  final List<LatLng> path;
  final String? summary;
  final double? distanceKm;
  final int? durationMins;
  final String? durationText;

  /// The stop being navigated to: the one matching [deliveryId], else the
  /// first.
  RouteStop? get target {
    for (final stop in stops) {
      if (stop.deliveryId == deliveryId) return stop;
    }
    return stops.isEmpty ? null : stops.first;
  }

  /// The road line to draw, or empty when there is no route to draw.
  List<LatLng> get line => path.length >= 2 ? path : const [];

  /// Every coordinate the camera should keep in view.
  List<LatLng> get coordinates => [...line, for (final s in stops) s.point];

  /// True when Directions returned trip stats (distance or drive time).
  bool get hasTripStats => distanceKm != null || durationMins != null;

  /// "11 mins", from [durationText] or [durationMins].
  String? get etaLabel =>
      durationText ?? (durationMins == null ? null : '$durationMins min');
}
