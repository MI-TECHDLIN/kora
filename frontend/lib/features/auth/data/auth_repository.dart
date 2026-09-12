import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/config/supabase_config.dart';

/// What the sign-up form sends to Supabase Auth.
class SignUpDetails {
  const SignUpDetails({
    required this.fullName,
    required this.email,
    required this.password,
    required this.phone,
  });

  final String fullName;
  final String email;
  final String password;

  /// E.164, e.g. `+2348012345678`.
  final String phone;
}

enum SignUpResult {
  /// The account exists and a session is live.
  signedIn,

  /// The project requires email confirmation: no session until the driver
  /// follows the link in their inbox, then signs in.
  confirmEmail,
}

/// A sign-up or sign-in attempt failed. [message] is safe to show a driver.
class AuthFailure implements Exception {
  const AuthFailure(this.message);
  final String message;

  @override
  String toString() => 'AuthFailure: $message';
}

/// The Supabase Auth account is fine, but the driver's `drivers` row could
/// not be created. [message] is for the driver; [detail] is for developers.
class DriverProfileException implements Exception {
  const DriverProfileException(this.message, {required this.detail});
  final String message;
  final String detail;

  @override
  String toString() => 'DriverProfileException: $detail';
}

/// Email + password and Google auth, straight against Supabase Auth. The
/// backend's phone-OTP routes (`/v1/auth/otp/*`) are a separate path and are
/// not used here.
abstract interface class AuthRepository {
  /// True while there is a session that has not expired.
  bool get hasValidSession;

  /// The session's access token, sent as `Authorization: Bearer <token>` on
  /// backend REST calls and the voice socket (docs/contracts/interface.md §4).
  /// Null when signed out.
  String? get accessToken;

  /// Fires on every sign-in, sign-out and token refresh.
  Stream<AuthChangeEvent> get changes;

  Future<SignUpResult> signUp(SignUpDetails details);

  Future<void> signIn({required String email, required String password});

  /// Starts Google sign-in in the browser. The session arrives later, through
  /// the [SupabaseConfig.authRedirectUrl] deep link, as a [changes] event.
  Future<void> signInWithGoogle();

  /// Creates the signed-in user's `drivers` row from their sign-up metadata
  /// if it does not exist yet. Throws [DriverProfileException] on failure.
  Future<void> ensureDriverProfile();
}

class SupabaseAuthRepository implements AuthRepository {
  SupabaseAuthRepository(this._client);

  final SupabaseClient _client;

  GoTrueClient get _auth => _client.auth;

  /// A null or expired session sends the driver back to the welcome screen.
  @visibleForTesting
  static bool isUsable(Session? session) =>
      session != null && !session.isExpired;

  @override
  bool get hasValidSession => isUsable(_auth.currentSession);

  @override
  String? get accessToken => _auth.currentSession?.accessToken;

  @override
  Stream<AuthChangeEvent> get changes =>
      _auth.onAuthStateChange.map((state) => state.event);

  // Mobile returns through the app's deep link; web returns to the site URL.
  String? get _redirectUrl => kIsWeb ? null : SupabaseConfig.authRedirectUrl;

  @override
  Future<SignUpResult> signUp(SignUpDetails details) async {
    final response = await _guard(
      () => _auth.signUp(
        email: details.email,
        password: details.password,
        emailRedirectTo: _redirectUrl,
        // Kept on the auth user so the drivers row can be created on first
        // sign-in when email confirmation holds back the session.
        data: {'full_name': details.fullName, 'phone': details.phone},
      ),
    );
    return response.session == null
        ? SignUpResult.confirmEmail
        : SignUpResult.signedIn;
  }

  @override
  Future<void> signIn({required String email, required String password}) =>
      _guard(() => _auth.signInWithPassword(email: email, password: password));

  @override
  Future<void> signInWithGoogle() async {
    final launched = await _guard(
      () =>
          _auth.signInWithOAuth(OAuthProvider.google, redirectTo: _redirectUrl),
    );
    if (!launched) {
      throw const AuthFailure("Couldn't open Google sign-in. Try again.");
    }
  }

  @override
  Future<void> ensureDriverProfile() async {
    final user = _auth.currentUser;
    if (user == null) return;
    final drivers = _client.from('drivers');
    final metadata = user.userMetadata ?? const {};

    final existing = await _profileCall(
      () => drivers.select('id').eq('id', user.id).maybeSingle(),
    );
    if (existing != null) return;

    final phone = metadata['phone'] as String?;
    if (phone == null || phone.isEmpty) {
      // Google accounts never went through the sign-up form, and
      // drivers.phone is NOT NULL.
      throw const DriverProfileException(
        _profileMessage,
        detail: 'no phone in user metadata; drivers.phone is NOT NULL',
      );
    }

    await _profileCall(
      () => drivers.insert({
        'id': user.id,
        'phone': phone,
        'name': metadata['full_name'],
      }),
    );
  }

  /// Runs a `drivers` query and turns every failure into a
  /// [DriverProfileException].
  Future<T> _profileCall<T>(Future<T> Function() call) async {
    try {
      return await call();
    } on PostgrestException catch (e) {
      throw DriverProfileException(
        _profileMessage,
        detail: switch (e.code) {
          // Known gap: drivers has SELECT/UPDATE RLS policies but no INSERT
          // policy, so the backend has to add one (or an endpoint).
          '42501' =>
            'drivers INSERT rejected by RLS (no INSERT policy): ${e.message}',
          '23505' => 'phone already belongs to another driver: ${e.message}',
          _ => 'drivers query failed (${e.code}): ${e.message}',
        },
      );
    } catch (e) {
      throw DriverProfileException(_profileMessage, detail: '$e');
    }
  }

  static const _profileMessage =
      "You're signed in, but your driver profile couldn't be set up yet. "
      'Deliveries stay unavailable until it is.';

  /// Runs an auth call and turns every failure into an [AuthFailure].
  Future<T> _guard<T>(Future<T> Function() call) async {
    if (!SupabaseConfig.isConfigured) {
      throw const AuthFailure(SupabaseConfig.notConfiguredMessage);
    }
    try {
      return await call();
    } on AuthRetryableFetchException {
      throw const AuthFailure(_offlineMessage);
    } on AuthException catch (e) {
      throw AuthFailure(switch (e.code) {
        'invalid_credentials' => "That email and password don't match.",
        'email_not_confirmed' =>
          'Confirm your email first. The link is in your inbox.',
        'user_already_exists' ||
        'email_exists' => 'That email already has an account. Sign in instead.',
        _ => e.message,
      });
    } catch (e) {
      debugPrint('Auth call failed: $e');
      throw const AuthFailure('Something went wrong. Try again.');
    }
  }

  static const _offlineMessage =
      "Can't reach VoiceOps right now. Check your connection and try again.";
}
