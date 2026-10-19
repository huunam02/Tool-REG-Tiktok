import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });
  tearDown(() {
    RemoteConfig.configs = RemoteConfig.defaults;
  });

  test(
    'OTP defaults use Remote Config defaults before Firebase starts',
    () async {
      RemoteConfig.configs = {};
      final settings = await const OtpSettingsStore().load();
      expect(settings.url, RemoteConfigKey.otp_api_url.defaultValue);
      expect(settings.token, RemoteConfigKey.otp_api_token.defaultValue);
    },
  );

  test(
    'OTP uses current remote values and ignores previously saved values',
    () async {
      SharedPreferences.setMockInitialValues({
        'otp_api_url': 'http://old.example.com/api/code',
        'otp_api_token': 'old-token',
      });
      RemoteConfig.configs[RemoteConfigKey.otp_api_url.name] =
          'https://remote.example.com/api/code';
      RemoteConfig.configs[RemoteConfigKey.otp_api_token.name] = 'remote-token';
      const store = OtpSettingsStore();
      final settings = await store.load();
      expect(settings.url, 'https://remote.example.com/api/code');
      expect(settings.toConfiguration().readerToken, 'remote-token');
      RemoteConfig.configs[RemoteConfigKey.otp_api_token.name] =
          'updated-token';
      expect((await store.load()).token, 'updated-token');
    },
  );
}
