import 'otp_api.dart';
import 'services/remote_config_service.dart';

class OtpApiSettings {
  const OtpApiSettings({required this.url, this.certificate = ''});

  factory OtpApiSettings.defaults() => OtpApiSettings(
    url: RemoteConfig.getString(RemoteConfigKey.otp_api_url),
    certificate: RemoteConfig.getString(RemoteConfigKey.otp_api_certificate),
  );

  final String url;

  /// Self-signed certificate trusted for [url]'s host; empty for none.
  final String certificate;

  OtpApiConfiguration toConfiguration() => OtpApiConfiguration(
    url: OtpApiConfiguration.parseUrl(url),
    trustedCertificate: certificate,
  );
}

/// API settings come exclusively from Firebase Remote Config.
class OtpSettingsStore {
  const OtpSettingsStore();
  static const instance = OtpSettingsStore();

  Future<OtpApiSettings> load() async => OtpApiSettings.defaults();
}
