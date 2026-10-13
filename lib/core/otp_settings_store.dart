import 'package:shared_preferences/shared_preferences.dart';

import 'config.dart' as defaults;
import 'otp_api.dart';

class OtpApiSettings {
  const OtpApiSettings({required this.url, required this.token});

  const OtpApiSettings.defaults()
      : url = defaults.otpApiUrl,
        token = defaults.otpApiToken;

  final String url;
  final String token;

  OtpApiConfiguration toConfiguration() => OtpApiConfiguration(
        url: OtpApiConfiguration.parseUrl(url),
        readerToken: token.trim(),
      );
}

class OtpSettingsStore {
  const OtpSettingsStore();

  static const instance = OtpSettingsStore();
  static const _urlKey = 'otp_api_url';
  static const _tokenKey = 'otp_api_token';

  Future<OtpApiSettings> load() async {
    final preferences = await SharedPreferences.getInstance();
    return OtpApiSettings(
      url: preferences.getString(_urlKey) ?? defaults.otpApiUrl,
      token: preferences.getString(_tokenKey) ?? defaults.otpApiToken,
    );
  }

  Future<void> save(OtpApiSettings settings) async {
    final preferences = await SharedPreferences.getInstance();
    await Future.wait([
      preferences.setString(_urlKey, settings.url.trim()),
      preferences.setString(_tokenKey, settings.token.trim()),
    ]);
  }
}
