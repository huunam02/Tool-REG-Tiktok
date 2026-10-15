import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/proxy_geolocation.dart';
import 'package:test_tiktok/core/app_configuration.dart';

import 'support/test_proxy_ip_platform.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late TestProxyIpPlatform platform;
  final proxy = WebViewProxy.parse(
    'proxy.example.com:8080',
    username: 'user',
    password: 'secret',
  )!;
  const valid =
      '{"success":true,"ip":"82.23.203.216","timezone":{"id":"America/New_York"}}';
  setUp(() {
    final previous = InAppWebViewPlatform.instance;
    platform = TestProxyIpPlatform();
    InAppWebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('test_tiktok/webview_identity'),
      (call) async => 'test-agent',
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  });
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  Future<ProxyGeolocation> lookup(ProxyGeolocationLookup checker) =>
      checker.lookup(proxy: proxy, userAgent: 'test-agent');

  test(
    'reads the API using the configured WebView proxy and disposes the probe',
    () async {
      final future = lookup(ProxyGeolocationLookup());
      await flush();
      final view = platform.probes.single;
      expect(view.controller.loadedRequest!.url!.host, 'ipwho.is');
      expect(view.controller.loadedRequest!.url!.scheme, 'https');
      expect(view.params.initialSettings!.cacheEnabled, isFalse);
      view.loaded(valid);
      final result = await future;
      expect(result.ip, '82.23.203.216');
      expect(result.timeZoneId, 'America/New_York');
      expect(view.disposed, isTrue);
    },
  );

  for (final payload in [
    '{"success":false,"ip":"82.23.203.216","timezone":{"id":"America/New_York"}}',
    '{"success":true,"ip":"bad","timezone":{"id":"America/New_York"}}',
    '{"success":true,"ip":"82.23.203.216","timezone":{"id":"America/New_York;command"}}',
    '{"success":true,"ip":"82.23.203.216"}',
  ]) {
    test('rejects malformed/failed API response: $payload', () {
      expect(
        () => ProxyGeolocation.fromJson(jsonDecode(payload)),
        throwsFormatException,
      );
    });
  }

  test('destination authentication never receives proxy credentials', () async {
    final future = lookup(ProxyGeolocationLookup());
    final assertion = expectLater(future, throwsFormatException);
    await flush();
    final view = platform.probes.single;
    Future<HttpAuthResponse?> auth(String host, int failures) =>
        view.params.onReceivedHttpAuthRequest!(
          view.callbackController,
          HttpAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: host),
            previousFailureCount: failures,
          ),
        );
    expect(await auth('ipwho.is', 0), isNull);
    final response = await auth('proxy.example.com', 1);
    expect(response!.username, 'user');
    expect(response.password, 'secret');
    expect(
      (await auth('proxy.example.com', 2))!.action,
      HttpAuthResponseAction.CANCEL,
    );
    await assertion;
    expect(platform.probes, hasLength(1));
    expect(view.disposed, isTrue);
  });

  test(
    'redirected responses are rejected without executing page JavaScript',
    () async {
      final future = lookup(ProxyGeolocationLookup());
      final assertion = expectLater(future, throwsFormatException);
      await flush();
      final view = platform.probes.single;
      view.loaded(valid, url: WebUri('https://unexpected.example/'));
      await assertion;
      expect(view.controller.scripts, isEmpty);
    },
  );

  test('timeout has no direct-network fallback', () async {
    await expectLater(
      lookup(ProxyGeolocationLookup(timeout: const Duration(milliseconds: 5))),
      throwsFormatException,
    );
    expect(platform.probes, hasLength(1));
    expect(platform.probes.single.disposed, isTrue);
  });

  test('late native startup is disposed after cancellation', () async {
    platform.startupGate = Completer<void>();
    final checker = ProxyGeolocationLookup();
    final future = lookup(checker);
    final assertion = expectLater(future, throwsFormatException);
    checker.cancel();
    await assertion;
    platform.startupGate!.complete();
    await flush();
    expect(platform.probes.single.disposed, isTrue);
  });
}
