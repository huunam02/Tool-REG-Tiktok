import 'app_configuration.dart';

class ProxyDraft {
  const ProxyDraft(this.name, this.proxy, this.userAgent);

  final String name;
  final WebViewProxy proxy;
  final String userAgent;
}
