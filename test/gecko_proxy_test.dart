import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/webview_proxy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('unqualified imported proxies default to HTTP', () {
    final proxy = WebViewProxy.parseImport('192.0.2.7:1080:user:pass');
    expect(proxy.uri, Uri.parse('http://192.0.2.7:1080'));
    expect(proxy.username, 'user');
    expect(proxy.password, 'pass');
    expect(WebViewProxy.parse('proxy.example:8080')!.uri.scheme, 'http');
  });

  test('explicit SOCKS5 and legacy stored proxy schemes remain readable', () {
    expect(
      WebViewProxy.parse('socks5://proxy.example:1080')?.uri.scheme,
      'socks5',
    );
    expect(
      WebViewProxy.parse('socks5h://proxy.example:1080')?.uri.scheme,
      'socks5h',
    );
    expect(
      WebViewProxy.parse('http://legacy.example:8080')?.uri.scheme,
      'http',
    );
  });

  test('explicit import protocols preserve the provider connection type', () {
    for (final scheme in ['http', 'https', 'socks5', 'socks5h']) {
      final proxy = WebViewProxy.parseImport(
        '$scheme://proxy.example:8080:user:pass:word',
      );
      expect(proxy.uri.scheme, scheme);
      expect(proxy.username, 'user');
      expect(proxy.password, 'pass:word');
    }
  });

  test(
    'VPN bridge keeps HTTP schemes and credentials and restores the original proxy',
    () async {
      const channel = MethodChannel('test_tiktok/profile_vpn');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final original = WebViewProxy.parse('socks5://original.example:1080')!;
      await configureWebViewProxy(original, profileId: 'original');
      calls.clear();
      for (final scheme in ['http', 'https']) {
        final proxy = WebViewProxy.parse(
          '$scheme://proxy.example:8080',
          username: 'u+ser',
          password: 'p:@ ss',
        )!;
        await withTemporaryWebViewProxy(proxy, () async {});
        final temporary = calls[calls.length - 2].arguments as Map;
        final uri = Uri.parse(temporary['proxy'] as String);
        expect(uri.scheme, scheme);
        expect(uri.host, 'proxy.example');
        expect(
          uri.userInfo,
          '${Uri.encodeComponent('u+ser')}:${Uri.encodeComponent('p:@ ss')}',
        );
        final restored = calls.last.arguments as Map;
        expect(restored['profileId'], 'original');
        expect(Uri.parse(restored['proxy'] as String).scheme, 'socks5');
      }
      await configureWebViewProxy(null);
    },
  );
}
