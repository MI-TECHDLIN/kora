/// Picovoice Porcupine wake-word configuration.
///
/// Supply the secret at build time; never commit it:
/// `flutter run --dart-define=PORCUPINE_ACCESS_KEY=<access-key>`.
abstract final class WakeWordConfig {
  static const accessKey = String.fromEnvironment('PORCUPINE_ACCESS_KEY');

  static bool get isConfigured => accessKey.trim().isNotEmpty;
}
