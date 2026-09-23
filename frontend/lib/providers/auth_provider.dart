import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/api/voiceops_api.dart';
import '../features/auth/data/auth_repository.dart';

/// The app's auth backend. Needs `Supabase.initialize` (see main.dart);
/// tests override it with a fake.
final authRepositoryProvider = Provider<AuthRepository>(
  (ref) => SupabaseAuthRepository(Supabase.instance.client),
);

enum DriverProfileStatus { syncing, ready, failed }

/// Whether the signed-in driver's `drivers` row is confirmed to exist on the
/// backend. [message] carries the last failure and is kept across a retry
/// attempt (status back to `syncing`) so a persistent banner can read
/// "Retrying…" instead of blinking away mid-attempt.
class DriverProfileState {
  const DriverProfileState({this.status = DriverProfileStatus.syncing, this.message});

  final DriverProfileStatus status;
  final String? message;

  /// True once there is something to tell the driver about — a live failure
  /// or a retry in flight. False before the first check ever completes.
  bool get needsAttention =>
      status != DriverProfileStatus.ready && message != null;
}

/// Confirms the signed-in driver's `drivers` row exists, via the backend's
/// idempotent `POST /v1/driver/ensure-profile` (docs/contracts/interface.md
/// §2; kora-full-audit report §2.1). Runs on every `signedIn` auth event
/// *and* immediately if a session already exists when this provider is
/// created — a restored session on app start never re-fires `signedIn`, so
/// without that a driver who reopened the app after a failed first attempt
/// would never get retried. [DriverProfileSync.retry] retries by hand from
/// a persistent banner ([DriverProfileNotice]) instead of a one-shot
/// SnackBar the driver could miss mid-sign-up.
final driverProfileProvider =
    StateNotifierProvider<DriverProfileSync, DriverProfileState>(
      (ref) => DriverProfileSync(
        ref.watch(koraApiProvider),
        ref.watch(authRepositoryProvider),
      ),
    );

class DriverProfileSync extends StateNotifier<DriverProfileState> {
  DriverProfileSync(this._api, this._auth) : super(const DriverProfileState()) {
    _subscription = _auth.changes
        .where((event) => event == AuthChangeEvent.signedIn)
        .listen((_) => _sync());
    if (_auth.hasValidSession) _sync();
  }

  final KoraApi _api;
  final AuthRepository _auth;
  late final StreamSubscription<AuthChangeEvent> _subscription;

  Future<void> retry() => _sync();

  Future<void> _sync() async {
    if (mounted) {
      state = DriverProfileState(
        status: DriverProfileStatus.syncing,
        message: state.message,
      );
    }
    try {
      await _api.ensureDriverProfile();
      if (mounted) state = const DriverProfileState(status: DriverProfileStatus.ready);
    } on ApiException catch (e) {
      debugPrint('Driver profile not confirmed: ${e.message}');
      if (mounted) {
        state = DriverProfileState(status: DriverProfileStatus.failed, message: e.message);
      }
    }
  }

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}
