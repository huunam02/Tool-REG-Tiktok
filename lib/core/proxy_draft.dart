import 'app_configuration.dart';
import 'configuration_data.dart';
import 'nurture_data.dart';

class ProxyDraft {
  const ProxyDraft(
    this.name,
    this.proxy,
    this.userAgent, {
    this.account,
    this.timeZoneId = '',
    this.statusAccount = AccountStatus.unregistered,
    this.nurtureAfterSignup = false,
    this.nurtureSettings = NurtureSettings.defaults,
    this.gpuProfileId,
  });

  final String name;
  final WebViewProxy? proxy;
  final String userAgent;
  final String timeZoneId;
  final AccountCredentials? account;
  final AccountStatus statusAccount;
  final bool nurtureAfterSignup;
  final NurtureSettings nurtureSettings;

  /// A [GpuProfile] id; null lets the store pick or keep one.
  final String? gpuProfileId;
}
