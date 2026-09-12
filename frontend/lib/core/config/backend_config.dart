/// Where the VoiceOps FastAPI backend lives, read at compile time:
///
/// ```sh
/// flutter run --dart-define=VOICEOPS_API_URL=https://<railway-app>.up.railway.app
/// ```
///
/// REST calls go to `<url>/v1/…` and the voice socket to
/// `<ws-url>/ws/voice/{shift_id}` (docs/contracts/interface.md §1–2). Unset,
/// the app still builds and boots; voice and profile calls then fail with
/// [notConfiguredMessage] instead of hitting the network.
abstract final class BackendConfig {
  static const url = String.fromEnvironment('VOICEOPS_API_URL');

  static bool get isConfigured => url.isNotEmpty;

  /// The backend base URL, or null when [isConfigured] is false.
  static Uri? get baseUri => isConfigured ? Uri.parse(url) : null;

  static const notConfiguredMessage =
      "Voice isn't set up in this build yet. Build with VOICEOPS_API_URL.";
}

/// `https://host/base` → `https://host/base/<path>`.
Uri restUri(Uri base, String path) =>
    base.replace(path: '${_trimSlash(base.path)}/$path');

/// The voice socket for [shiftId]: same host, `ws`/`wss` scheme.
Uri voiceSocketUri(Uri base, String shiftId) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '${_trimSlash(base.path)}/ws/voice/${Uri.encodeComponent(shiftId)}',
);

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;
