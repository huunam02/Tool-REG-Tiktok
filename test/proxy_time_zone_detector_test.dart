import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/proxy_time_zone_detector.dart';
import 'package:test_tiktok/core/webview_proxy.dart';

import 'support/test_proxy_ip_platform.dart';

final proxyController = _Proxy(const PlatformProxyControllerCreationParams());

class _Platform extends TestProxyIpPlatform {
  @override
  PlatformWebViewFeature createPlatformWebViewFeatureStatic() =>
      _Features(const PlatformWebViewFeatureCreationParams());
  @override
  PlatformProxyController createPlatformProxyController(
    PlatformProxyControllerCreationParams params,
  ) => proxyController;
}

class _Features extends PlatformWebViewFeature {
  _Features(super.params) : super.implementation();
  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async => true;
}

class _Proxy extends PlatformProxyController {
  _Proxy(super.params) : super.implementation();
  final calls = <String>[];
  @override
  Future<void> setProxyOverride({required ProxySettings settings}) async =>
      calls.add(settings.proxyRules.single.url);
  @override
  Future<void> clearProxyOverride() async => calls.add('direct');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_tiktok/webview_identity');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late _Platform platform;
  final original = WebViewProxy.parse('original.example:8080')!;
  final firstProxy = WebViewProxy.parse(
    'first.example:8080',
    username: 'user1',
    password: 'pass1',
  )!;
  final secondProxy = WebViewProxy.parse(
    'second.example:8080',
    username: 'user2',
    password: 'pass2',
  )!;
  const us =
      '{"success":true,"ip":"82.23.203.216","timezone":{"id":"America/New_York"}}';
  Future<void> flush() => Future<void>.delayed(Duration.zero);
  setUp(() async {
    final previous = InAppWebViewPlatform.instance;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(channel, (_) async => 'agent');
    await configureWebViewProxy(original);
    proxyController.calls.clear();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previous != null) InAppWebViewPlatform.instance = previous;
      messenger.setMockMethodCallHandler(channel, null);
    });
  });

  test(
    'batch lookups use one proxy at a time and restore original after each',
    () async {
      final detector = ProxyTimeZoneDetector();
      final first = detector.detect(firstProxy, 'agent');
      final second = detector.detect(secondProxy, 'agent');
      await flush();
      expect(platform.probes, hasLength(1));
      final auth =
          await platform.probes.first.params.onReceivedHttpAuthRequest!(
            platform.probes.first.callbackController,
            HttpAuthenticationChallenge(
              protectionSpace: URLProtectionSpace(host: 'first.example'),
              previousFailureCount: 1,
            ),
          );
      expect(auth!.username, 'user1');
      platform.probes.first.loaded(us);
      expect(await first, 'America/New_York');
      await flush();
      expect(platform.probes.first.disposed, isTrue);
      expect(platform.probes, hasLength(2));
      platform.probes.last.loaded(
        us.replaceAll('America/New_York', 'Asia/Tokyo'),
      );
      expect(await second, 'Asia/Tokyo');
      expect(proxyController.calls, [
        firstProxy.uri.toString(),
        original.uri.toString(),
        secondProxy.uri.toString(),
        original.uri.toString(),
      ]);
      expect(platform.probes.every((view) => view.disposed), isTrue);
    },
  );

  test(
    'closing cancels active lookup and skips queued proxies without changing selection',
    () async {
      final detector = ProxyTimeZoneDetector();
      final first = expectLater(
        detector.detect(firstProxy, 'agent'),
        throwsFormatException,
      );
      final second = expectLater(
        detector.detect(secondProxy, 'agent'),
        throwsFormatException,
      );
      await flush();
      expect(platform.probes, hasLength(1));
      detector.cancel();
      await Future.wait([first, second]);
      expect(proxyController.calls, [
        firstProxy.uri.toString(),
        original.uri.toString(),
      ]);
      expect(platform.probes.single.disposed, isTrue);
    },
  );
}
