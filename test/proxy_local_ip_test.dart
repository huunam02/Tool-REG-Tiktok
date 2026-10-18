import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_local_ip.dart';
import 'package:test_tiktok/core/webview_privacy.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'same endpoint retains its address across credential changes and reloads',
    () async {
      final first = WebViewProxy.parse(
        'proxy.example:8080',
        username: 'u',
        password: 'secret',
      )!;
      final second = WebViewProxy.parse(
        'http://PROXY.EXAMPLE:8080',
        username: 'other',
        password: 'rotated',
      )!;
      final ip = await loadProxyLocalIp(first);
      expect(isSimulatedLocalIp(ip), isTrue);
      expect(await loadProxyLocalIp(second), ip);
      final prefs = await SharedPreferences.getInstance();
      final saved = {for (final key in prefs.getKeys()) key: prefs.get(key)!};
      expect(jsonEncode(saved), isNot(contains('secret')));
      expect(jsonEncode(saved), isNot(contains('rotated')));
      SharedPreferences.setMockInitialValues(saved);
      expect(await loadProxyLocalIp(first), ip);
    },
  );

  test('concurrent endpoints get distinct persisted addresses', () async {
    final proxies = [
      WebViewProxy.parse('proxy.example:8080')!,
      WebViewProxy.parse('proxy.example:8081')!,
      WebViewProxy.parse('https://proxy.example:8080')!,
      WebViewProxy.parse('other.example:8080')!,
    ];
    final ips = await Future.wait(proxies.map(loadProxyLocalIp));
    expect(ips.toSet(), hasLength(proxies.length));
    expect(ips.every(isSimulatedLocalIp), isTrue);
    expect(ips, isNot(contains(defaultSimulatedLocalIp)));
    expect(await Future.wait(proxies.map(loadProxyLocalIp)), ips);
    expect(await loadProxyLocalIp(null), defaultSimulatedLocalIp);
  });

  test(
    'damaged storage recovers and script rejects unsafe or public addresses',
    () async {
      SharedPreferences.setMockInitialValues({
        'webview_proxy_local_ips_v1': '{broken',
      });
      final ip = await loadProxyLocalIp(
        WebViewProxy.parse('proxy.example:8080'),
      );
      expect(webRtcLocalIpScript(ip), disableWebRtcScript);
      expect(webRtcLocalIpScript(ip), isNot(contains(ip)));
      for (final valid in ['10.0.0.1', '172.16.5.9', '172.31.255.254']) {
        expect(isSimulatedLocalIp(valid), isTrue, reason: valid);
      }
      for (final invalid in [
        '8.8.8.8',
        '172.15.0.1',
        '172.32.0.1',
        '100.64.0.1',
        '10.0.0.0',
        '10.01.0.1',
        '192.168.1.0',
        '192.168.1.255',
        '192.168.256.1',
        "192.168.1.1';alert(1)//",
      ]) {
        expect(() => webRtcLocalIpScript(invalid), throwsFormatException);
      }
    },
  );
}
