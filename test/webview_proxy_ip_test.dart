import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/webview_proxy_ip.dart';

import 'support/test_proxy_ip_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestProxyIpPlatform platform;
  setUp(() {
    final previousPlatform = InAppWebViewPlatform.instance;
    platform = TestProxyIpPlatform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(() {
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
      debugDefaultTargetPlatformOverride = null;
    });
  });

  Future<String?> check(WebViewProxyIpChecker checker) => checker.check(
      userAgent: 'test-agent', onAuth: (controller, challenge) async => null);

  Future<void> flush() => Future<void>.delayed(Duration.zero);

  for (final target in [TargetPlatform.android, TargetPlatform.iOS]) {
    test('$target reads IP without executing fetch in TikTok', () async {
      debugDefaultTargetPlatformOverride = target;
      final result = check(WebViewProxyIpChecker());
      final view = platform.probes.single;
      expect(view.params.initialUrlRequest!.url!.host, 'api.ipify.org');
      expect(
          view.params.initialUrlRequest!.headers?['Accept-Language'], isNull);
      expect(
          view.params.initialUrlRequest!.headers?['Cache-Control'], 'no-cache');
      expect(view.params.initialSettings!.incognito, isFalse);
      expect(view.params.initialSettings!.cacheEnabled, isTrue);
      expect(view.params.initialSettings!.userAgent, 'test-agent');
      expect(view.params.initialSettings!.preferredContentMode,
          UserPreferredContentMode.DESKTOP);
      view.loaded('{"ip":"203.0.113.7"}');
      expect(await result, '203.0.113.7');
      expect(view.controller.scripts, ['document.body.innerText']);
      expect(view.disposed, isTrue);
    });
  }

  test('fallback also uses WebView and accepts IPv6', () async {
    final result = check(WebViewProxyIpChecker());
    final first = platform.probes.single;
    first.failed();
    await flush();
    expect(first.disposed, isTrue);
    final fallback = platform.probes.last;
    expect(fallback.params.initialUrlRequest!.url!.host, 'api64.ipify.org');
    fallback.loaded('{"ip":"2001:db8::7"}');
    expect(await result, '2001:db8::7');
    expect(fallback.disposed, isTrue);
  });

  test('invalid IP and redirected pages cannot be reported as IP', () async {
    final result = check(WebViewProxyIpChecker());
    platform.probes.single.loaded('{"ip":"proxy error"}');
    await flush();
    final fallback = platform.probes.last;
    fallback.loaded('{"ip":"203.0.113.7"}',
        url: WebUri('https://unexpected.example/'));
    expect(await result, isNull);
    expect(fallback.controller.scripts, isEmpty);
  });

  test('timeout releases both WebViews', () async {
    final result =
        check(WebViewProxyIpChecker(timeout: const Duration(milliseconds: 5)));
    expect(await result, isNull);
    expect(platform.probes, hasLength(2));
    expect(platform.probes.every((view) => view.disposed), isTrue);
  });

  test('cancellation disposes and prevents fallback', () async {
    final checker = WebViewProxyIpChecker();
    final result = check(checker);
    checker.cancel();
    expect(await result, isNull);
    expect(platform.probes, hasLength(1));
    expect(platform.probes.single.disposed, isTrue);
  });

  test('a native view that starts after cancellation is still released',
      () async {
    platform.startupGate = Completer<void>();
    final checker = WebViewProxyIpChecker();
    final result = check(checker);
    checker.cancel();
    expect(await result, isNull);
    expect(platform.probes.single.disposed, isFalse);
    platform.startupGate!.complete();
    await flush();
    expect(platform.probes.single.disposed, isTrue);
    expect(platform.probes, hasLength(1));
  });

  test('auth callback receives challenge and rejected auth stops fallback',
      () async {
    final challenge = HttpAuthenticationChallenge(
        protectionSpace: URLProtectionSpace(host: 'proxy.example.com'),
        previousFailureCount: 2);
    final result = WebViewProxyIpChecker().check(
        userAgent: 'test-agent',
        onAuth: (controller, received) async {
          expect(received, same(challenge));
          return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
        });
    final view = platform.probes.single;
    final response = await view.params.onReceivedHttpAuthRequest!(
        view.callbackController, challenge);
    expect(response!.action, HttpAuthResponseAction.CANCEL);
    expect(await result, isNull);
    expect(platform.probes, hasLength(1));
    expect(view.disposed, isTrue);
  });
}
