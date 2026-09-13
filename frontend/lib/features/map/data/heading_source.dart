import 'package:flutter_compass/flutter_compass.dart';

/// Device heading in degrees clockwise from magnetic north.
///
/// Unlike a GPS course, this continues to update while the driver is stopped
/// and turns their phone. Tests replace it so no sensor channel is touched.
abstract interface class HeadingSource {
  Stream<double> watch();
}

class CompassHeadingSource implements HeadingSource {
  const CompassHeadingSource();

  @override
  Stream<double> watch() {
    final events = FlutterCompass.events;
    if (events == null) return const Stream.empty();
    return events
        .where((event) => event.heading != null)
        .map((event) => _normalise(event.heading!));
  }

  static double _normalise(double heading) => (heading % 360 + 360) % 360;
}
