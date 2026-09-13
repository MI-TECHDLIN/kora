import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// One position fix for the driver's marker.
class LocationFix {
  const LocationFix(this.point, {this.heading, this.speed});

  final LatLng point;

  /// Degrees clockwise from north, or null when unknown or standing still.
  final double? heading;

  /// Metres per second, or null when unknown.
  final double? speed;
}

enum LocationProblem { serviceOff, denied, deniedForever, unavailable }

/// Why the driver's position can't be shown. [message] is safe to show.
class LocationUnavailable implements Exception {
  const LocationUnavailable(this.problem);
  final LocationProblem problem;

  String get message => switch (problem) {
    LocationProblem.serviceOff =>
      'Location is off. Turn it on to see where you are.',
    LocationProblem.denied =>
      'VoiceOps needs your location to show you on the map.',
    LocationProblem.deniedForever =>
      'Location is blocked for VoiceOps. Allow it in Settings.',
    LocationProblem.unavailable => "Can't find your location right now.",
  };

  @override
  String toString() => 'LocationUnavailable: $problem';
}

/// The driver's live position. Tests override `locationSourceProvider` with
/// a fake so no platform channel is touched.
abstract interface class LocationSource {
  /// Asks for permission if needed, then streams fixes. Errors with
  /// [LocationUnavailable] when location can't be used.
  Stream<LocationFix> watch();

  /// Opens the system screen that fixes [problem] (location or app settings).
  Future<void> openSettings(LocationProblem problem);
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  @override
  Stream<LocationFix> watch() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationProblem.serviceOff);
    }
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    switch (permission) {
      case LocationPermission.denied:
        throw const LocationUnavailable(LocationProblem.denied);
      case LocationPermission.deniedForever:
        throw const LocationUnavailable(LocationProblem.deniedForever);
      case LocationPermission.unableToDetermine:
        throw const LocationUnavailable(LocationProblem.unavailable);
      case LocationPermission.whileInUse || LocationPermission.always:
        break;
    }
    try {
      yield* Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).map(
        (p) => LocationFix(
          LatLng(p.latitude, p.longitude),
          // Heading is noise while stopped.
          heading: p.speed > 1 && p.heading >= 0 ? p.heading : null,
          speed: p.speed >= 0 ? p.speed : null,
        ),
      );
    } on LocationServiceDisabledException {
      throw const LocationUnavailable(LocationProblem.serviceOff);
    }
  }

  @override
  Future<void> openSettings(LocationProblem problem) async {
    if (problem == LocationProblem.serviceOff) {
      await Geolocator.openLocationSettings();
    } else {
      await Geolocator.openAppSettings();
    }
  }
}
