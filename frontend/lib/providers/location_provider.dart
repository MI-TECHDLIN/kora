import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/map/data/location_source.dart';

/// Where fixes come from. Tests override this with a fake.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// The driver's live position, started by the app's map warmup and shared with
/// the Map tab. Errors with [LocationUnavailable]; invalidate it to ask again.
final locationProvider = StreamProvider<LocationFix>(
  (ref) => ref.watch(locationSourceProvider).watch(),
);
