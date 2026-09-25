import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/api/voiceops_api.dart';
import 'auth_provider.dart';

/// The signed-in driver's profile (name, vehicle) from
/// `GET /v1/driver/profile`. The read waits for the startup/sign-in
/// `POST /v1/driver/ensure-profile`, so a first request cannot cache a 404
/// while the backend is still creating the row.
final driverDetailsProvider = FutureProvider<DriverProfile>((ref) async {
  final sync = await ref.watch(driverProfileProvider.notifier).settled;
  if (sync.status == DriverProfileStatus.failed) {
    throw ApiException(sync.message ?? "Couldn't set up your driver profile.");
  }
  return ref.watch(koraApiProvider).fetchDriverProfile();
});

/// Re-checks row readiness as well as the GET. This preserves the existing
/// Retry affordance for both ensure-profile failures and transient reads.
void retryDriverDetails(WidgetRef ref) {
  unawaited(ref.read(driverProfileProvider.notifier).retry());
  ref.invalidate(driverDetailsProvider);
}
