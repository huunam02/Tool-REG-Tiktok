import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({
      'sadcaptcha_license_key': 'old-saved-key',
    });
    RemoteConfig.configs = {
      ...RemoteConfig.defaults,
      'sadcaptcha_license_key': 'remote-fixture-key',
    };
  });
  tearDown(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });

  test(
    'CAPTCHA uses Remote Config and ignores previously saved keys',
    () async {
      final store = CaptchaSettingsStore();
      expect((await store.load()).licenseKey, 'remote-fixture-key');
      RemoteConfig.configs[RemoteConfigKey.sadcaptcha_license_key.name] = '';
      expect((await store.load()).licenseKey, isEmpty);
      expect(store.effectiveLicenseKey, isEmpty);
      store.dispose();
    },
  );
}
