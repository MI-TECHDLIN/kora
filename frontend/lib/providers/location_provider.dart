import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/map/data/location_source.dart';

/// Where fixes come from. Tests override this with a fake.
final locationSourceProvider = Provider<LocationSource>(
  (ref) => const GeolocatorLocationSource(),
);

/// The driver's live position while something watches it (the Map tab).
/// Errors with [LocationUnavailable]; invalidate it to ask again.
final locationProvider = StreamProvider.autoDispose<LocationFix>(
  (ref) => ref.watch(locationSourceProvider).watch(),
);
