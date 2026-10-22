import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';

void main() {
  test('unqualified imported proxies default to SOCKS5', () {
    final proxy = WebViewProxy.parseImport('192.0.2.7:1080:user:pass');
    expect(proxy.uri, Uri.parse('socks5://192.0.2.7:1080'));
    expect(proxy.username, 'user');
    expect(proxy.password, 'pass');
  });

  test('explicit SOCKS5 and legacy stored proxy schemes remain readable', () {
    expect(WebViewProxy.parse('socks5://proxy.example:1080')?.uri.scheme, 'socks5');
    expect(WebViewProxy.parse('socks5h://proxy.example:1080')?.uri.scheme, 'socks5h');
    expect(WebViewProxy.parse('http://legacy.example:8080')?.uri.scheme, 'http');
  });
}
