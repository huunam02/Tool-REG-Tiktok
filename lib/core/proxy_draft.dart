import 'app_configuration.dart';
import 'configuration_data.dart';

class ProxyDraft {
  const ProxyDraft(
    this.name,
    this.proxy,
    this.userAgent, {
    this.account,
    this.statusAccount = AccountStatus.unregistered,
  });

  final String name;
  final WebViewProxy proxy;
  final String userAgent;
  final AccountCredentials? account;
  final AccountStatus statusAccount;
}
