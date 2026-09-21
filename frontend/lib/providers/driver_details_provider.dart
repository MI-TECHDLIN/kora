import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';

/// The signed-in driver's profile (name, vehicle) from
/// `GET /v1/driver/profile`. Invalidate it to retry.
final driverDetailsProvider = FutureProvider<DriverProfile>(
  (ref) => ref.watch(koraApiProvider).fetchDriverProfile(),
);
