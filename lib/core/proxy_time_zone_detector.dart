import 'app_configuration.dart';
import 'proxy_geolocation.dart';
import 'webview_proxy.dart';
import 'webview_user_agent.dart';

class ProxyTimeZoneDetector {
  ProxyGeolocationLookup? _lookup;
  bool _cancelled = false;

  Future<String> detect(WebViewProxy proxy, String userAgent) async {
    if (_cancelled) throw const FormatException('Đã hủy tra múi giờ.');
    final agent = await resolveWebViewUserAgent(userAgent);
    if (_cancelled) throw const FormatException('Đã hủy tra múi giờ.');
    return withTemporaryWebViewProxy(proxy, () async {
      if (_cancelled) throw const FormatException('Đã hủy tra múi giờ.');
      final lookup = ProxyGeolocationLookup();
      _lookup = lookup;
      try {
        return (await lookup.lookup(proxy: proxy, userAgent: agent)).timeZoneId;
      } finally {
        if (identical(_lookup, lookup)) _lookup = null;
      }
    }, isCancelled: () => _cancelled);
  }

  void cancel() {
    _cancelled = true;
    _lookup?.cancel();
  }
}
