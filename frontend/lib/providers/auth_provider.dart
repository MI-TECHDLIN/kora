import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/data/auth_repository.dart';

/// The app's auth backend. Needs `Supabase.initialize` (see main.dart);
/// tests override it with a fake.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);

/// The latest failure to create the signed-in driver's `drivers` row, or
/// null. Every sign-in (email, Google, or sign-up with a live session) runs
/// [AuthRepository.ensureDriverProfile]; a failure lands here, is logged,
/// and is shown to the driver rather than dropped.
final driverProfileProvider =
    StateNotifierProvider<DriverProfileSync, DriverProfileException?>(
      (ref) => DriverProfileSync(ref.watch(authRepositoryProvider)),
    );

class DriverProfileSync extends StateNotifier<DriverProfileException?> {
  DriverProfileSync(this._repository) : super(null) {
    _subscription = _repository.changes
        .where((event) => event == AuthChangeEvent.signedIn)
        .listen((_) => _sync());
  }

  final AuthRepository _repository;
  late final StreamSubscription<AuthChangeEvent> _subscription;

  Future<void> _sync() async {
    try {
      await _repository.ensureDriverProfile();
      if (mounted) state = null;
    } on DriverProfileException catch (e) {
      debugPrint('Driver profile not created: ${e.detail}');
      if (mounted) state = e;
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
