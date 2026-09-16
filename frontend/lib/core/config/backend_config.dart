/// Where the VoiceOps FastAPI backend lives.
///
/// Builds use the production Render deployment by default. Override it at
/// compile time for local development with:
/// `flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000`.
///
/// REST calls go to `<url>/v1/...` and the voice socket to
/// `<ws-url>/ws/voice/{shift_id}` (docs/contracts/interface.md sections 1-2).
abstract final class BackendConfig {
  /// Production backend URL (Render deployment).
  static const productionUrl = 'https://voiceops-ll41.onrender.com';

  static const url = String.fromEnvironment(
    'VOICEOPS_API_URL',
    defaultValue: productionUrl,
  );

  static bool get isConfigured => url.isNotEmpty;

  /// The backend base URL, or null if an explicitly empty override is passed.
  static Uri? get baseUri => isConfigured ? Uri.parse(url) : null;

  static const notConfiguredMessage =
      "Voice isn't set up in this build yet. Build with VOICEOPS_API_URL.";
}

/// `https://host/base` -> `https://host/base/<path>`.
Uri restUri(Uri base, String path) =>
    base.replace(path: '${_trimSlash(base.path)}/$path');

/// The voice socket for [shiftId]: same host, `ws`/`wss` scheme.
Uri voiceSocketUri(Uri base, String shiftId) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '${_trimSlash(base.path)}/ws/voice/${Uri.encodeComponent(shiftId)}',
);

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;
