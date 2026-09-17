import 'package:flutter_test/flutter_test.dart';
import 'package:voiceops/core/config/backend_config.dart';

const _overrideUrl = String.fromEnvironment('VOICEOPS_API_URL');

void main() {
  if (!const bool.hasEnvironment('VOICEOPS_API_URL')) {
    test('defaults to the production backend without a dart define', () {
      expect(BackendConfig.url, BackendConfig.productionUrl);
      expect(BackendConfig.baseUri, Uri.parse(BackendConfig.productionUrl));
      expect(BackendConfig.isConfigured, isTrue);
    });
  } else if (_overrideUrl.isEmpty) {
    test('an explicitly empty override leaves the backend unconfigured', () {
      expect(BackendConfig.url, isEmpty);
      expect(BackendConfig.baseUri, isNull);
      expect(BackendConfig.isConfigured, isFalse);
    });
  } else {
    test('VOICEOPS_API_URL overrides the production backend', () {
      expect(BackendConfig.url, _overrideUrl);
      expect(BackendConfig.baseUri, Uri.parse(_overrideUrl));
      expect(BackendConfig.isConfigured, isTrue);
    });
  }
}
