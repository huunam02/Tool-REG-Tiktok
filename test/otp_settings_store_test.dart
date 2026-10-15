import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/config.dart' as defaults;
import 'package:test_tiktok/core/otp_settings_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('OTP settings use defaults and persist edited values', () async {
    const store = OtpSettingsStore();
    final initial = await store.load();
    expect(initial.url, defaults.otpApiUrl);
    expect(initial.token, defaults.otpApiToken);

    const edited = OtpApiSettings(
      url: 'http://10.0.2.2:5678/api/code',
      token: 'new-reader-token',
    );
    await store.save(edited);

    final restored = await const OtpSettingsStore().load();
    expect(restored.url, edited.url);
    expect(restored.token, edited.token);
    expect(restored.toConfiguration().url.toString(), edited.url);
    expect(restored.toConfiguration().readerToken, edited.token);
  });
}
