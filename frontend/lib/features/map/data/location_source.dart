import 'dart:async';

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

/// One position fix for the driver's marker.
class LocationFix {
  const LocationFix(this.point, {this.heading, this.speed, this.accuracy});

  final LatLng point;

  /// Degrees clockwise from north, or null when unknown or standing still.
  final double? heading;

  /// Metres per second, or null when unknown.
  final double? speed;

  /// Radius of 68% confidence in metres, or null when unknown. The marker
  /// ignores it; it rides along for the backend's GPS ping.
  final double? accuracy;
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
      'Kora needs your location to show you on the map.',
    LocationProblem.deniedForever =>
      'Location is blocked for Kora. Allow it in Settings.',
    LocationProblem.unavailable => "Can't find your location right now.",
  };

  @override
  String toString() => 'LocationUnavailable: $problem';
}

/// The driver's live position. Tests override `locationSourceProvider` with
/// a fake so no platform channel is touched.
abstract interface class LocationSource {
  /// Whether location is already allowed. Never asks.
  Future<bool> hasPermission();

  /// Asks for location permission if the OS still lets the app ask; true
  /// once allowed. Onboarding's Power screen asks, and the map asks again
  /// only when the driver taps to allow.
  Future<bool> requestPermission();

  /// Streams fixes. Never asks for permission: errors with
  /// [LocationUnavailable] when location can't be used, including before
  /// [requestPermission] is granted.
  Stream<LocationFix> watch();

  /// Opens the system screen that fixes [problem] (location or app settings).
  Future<void> openSettings(LocationProblem problem);
}

class GeolocatorLocationSource implements LocationSource {
  const GeolocatorLocationSource();

  static bool _allowed(LocationPermission permission) =>
      permission == LocationPermission.whileInUse ||
      permission == LocationPermission.always;

  @override
  Future<bool> hasPermission() async =>
      _allowed(await Geolocator.checkPermission());

  @override
  Future<bool> requestPermission() async {
    var permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }
    return _allowed(permission);
  }

  @override
  Stream<LocationFix> watch() async* {
    if (!await Geolocator.isLocationServiceEnabled()) {
      throw const LocationUnavailable(LocationProblem.serviceOff);
    }
    switch (await Geolocator.checkPermission()) {
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
          accuracy: p.accuracy >= 0 ? p.accuracy : null,
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
