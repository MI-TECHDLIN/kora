import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/map/data/heading_source.dart';

/// Where device-heading updates come from. Tests override this with a fake.
final headingSourceProvider = Provider<HeadingSource>(
  (ref) => const CompassHeadingSource(),
);

/// The phone's live compass heading. GPS course remains the map's fallback on
/// devices without a heading sensor.
final headingProvider = StreamProvider<double>(
  (ref) => ref.watch(headingSourceProvider).watch(),
);
