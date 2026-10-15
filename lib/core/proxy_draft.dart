import 'app_configuration.dart';
import 'configuration_data.dart';

class ProxyDraft {
  const ProxyDraft(
    this.name,
    this.proxy,
    this.userAgent, {
    this.account,
    this.timeZoneId = '',
    this.statusAccount = AccountStatus.unregistered,
  });

  final String name;
  final WebViewProxy? proxy;
  final String userAgent;
  final String timeZoneId;
  final AccountCredentials? account;
  final AccountStatus statusAccount;
}
