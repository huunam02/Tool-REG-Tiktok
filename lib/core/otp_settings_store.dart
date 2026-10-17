import 'otp_api.dart';
import 'services/remote_config_service.dart';

class OtpApiSettings {
  const OtpApiSettings({required this.url, required this.token});

  factory OtpApiSettings.defaults() => OtpApiSettings(
    url: RemoteConfig.getString(RemoteConfigKey.otp_api_url),
    token: RemoteConfig.getString(RemoteConfigKey.otp_api_token),
  );

  final String url;
  final String token;

  OtpApiConfiguration toConfiguration() => OtpApiConfiguration(
    url: OtpApiConfiguration.parseUrl(url),
    readerToken: token.trim(),
  );
}

/// API settings come exclusively from Firebase Remote Config.
class OtpSettingsStore {
  const OtpSettingsStore();
  static const instance = OtpSettingsStore();

  Future<OtpApiSettings> load() async => OtpApiSettings.defaults();
}
