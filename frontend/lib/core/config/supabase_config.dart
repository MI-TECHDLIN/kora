/// Supabase connection settings, read at compile time:
///
/// ```sh
/// flutter run \
///   --dart-define=SUPABASE_URL=https://<project-ref>.supabase.co \
///   --dart-define=SUPABASE_ANON_KEY=<anon key>
/// ```
///
/// Only the anon (publishable) key ever belongs in the app. The service-role
/// key bypasses row-level security and must never ship in a client.
///
/// Unset values fall back to obviously fake placeholders, so the app still
/// builds and boots without credentials; auth calls then fail with
/// [notConfiguredMessage] instead of hitting the network.
abstract final class SupabaseConfig {
  static const url = String.fromEnvironment(
    'SUPABASE_URL',
    defaultValue: _placeholderUrl,
  );

  static const anonKey = String.fromEnvironment(
    'SUPABASE_ANON_KEY',
    defaultValue: _placeholderAnonKey,
  );

  // `.invalid` is a reserved TLD (RFC 2606): it never resolves anywhere.
  static const _placeholderUrl = 'https://supabase-url-not-set.invalid';
  static const _placeholderAnonKey = 'supabase-anon-key-not-set';

  static bool get isConfigured =>
      url != _placeholderUrl && anonKey != _placeholderAnonKey;

  static const notConfiguredMessage =
      "Sign-in isn't set up in this build yet. "
      'Build with SUPABASE_URL and SUPABASE_ANON_KEY.';

  /// Where OAuth (Google) and email-confirmation links return to on mobile.
  /// Registered as a deep link in AndroidManifest.xml and ios Info.plist, and
  /// must be added to the Supabase project's allowed redirect URLs.
  static const authRedirectUrl = 'io.voiceops.app://login-callback/';
}
