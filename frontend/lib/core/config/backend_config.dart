/// Where the Kora FastAPI backend lives.
///
/// Builds use the production Render deployment by default. Override it at
/// compile time for local development with:
/// `flutter run --dart-define=VOICEOPS_API_URL=http://localhost:8000`.
///
/// REST calls go to `<url>/v1/...` and the voice socket to
/// `<ws-url>/ws/voice/{shift_id}` (docs/contracts/interface.md sections 1-2).
abstract final class BackendConfig {
  /// Production backend URL (Render deployment).
  static const productionUrl = 'https://kora-brd8.onrender.com';

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

/// The voice socket for [shiftId]: same host, `ws`/`wss` scheme. [voice] is
/// the co-rider's stock voice, sent as `?voice=<id>`; the backend applies it
/// at session start and falls back to Anna when it's missing or unknown.
Uri voiceSocketUri(Uri base, String shiftId, {String? voice}) => base.replace(
  scheme: base.scheme == 'https' ? 'wss' : 'ws',
  path: '${_trimSlash(base.path)}/ws/voice/${Uri.encodeComponent(shiftId)}',
  queryParameters: voice == null ? null : {'voice': voice},
);

String _trimSlash(String path) =>
    path.endsWith('/') ? path.substring(0, path.length - 1) : path;

/// Where the app is talking to, for messages and Settings: `host[:port]`, or
/// "no backend" when none is configured.
String backendLabel(Uri? base) {
  if (base == null || base.host.isEmpty) return 'no backend';
  final defaultPort = base.scheme == 'https' ? 443 : 80;
  return base.hasPort && base.port != defaultPort
      ? '${base.host}:${base.port}'
      : base.host;
}

/// Whether [base] is an address a phone away from the developer's computer
/// can't reach in production: plain http, or a loopback / LAN address. A
/// release build pointed at one talks to nothing on Render (see
/// `config/supabase.prod.json.example`).
bool isDevelopmentBackend(Uri? base) {
  if (base == null) return false;
  if (base.scheme != 'https') return true;
  final host = base.host;
  return host == 'localhost' ||
      host.endsWith('.local') ||
      RegExp(
        r'^(127\.|10\.|192\.168\.|172\.(1[6-9]|2\d|3[01])\.|169\.254\.)',
      ).hasMatch(host);
}
