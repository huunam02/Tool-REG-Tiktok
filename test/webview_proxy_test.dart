import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/webview_proxy.dart';

final _proxy = _Proxy(const PlatformProxyControllerCreationParams());

class _Platform extends InAppWebViewPlatform {
  final unsupported = <WebViewFeature>{};

  @override
  PlatformWebViewFeature createPlatformWebViewFeatureStatic() =>
      _Features(const PlatformWebViewFeatureCreationParams(), unsupported);

  @override
  PlatformProxyController createPlatformProxyController(
    PlatformProxyControllerCreationParams params,
  ) => _proxy;
}

class _Features extends PlatformWebViewFeature {
  _Features(super.params, this.unsupported) : super.implementation();
  final Set<WebViewFeature> unsupported;

  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async =>
      !unsupported.contains(feature);
}

class _Proxy extends PlatformProxyController {
  _Proxy(super.params) : super.implementation();
  ProxySettings? settings;
  int clears = 0;
  final calls = <String>[];

  @override
  Future<void> setProxyOverride({required ProxySettings settings}) async {
    this.settings = settings;
    calls.add(settings.proxyRules.single.url);
  }

  @override
  Future<void> clearProxyOverride() async {
    clears++;
    calls.add('direct');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  final proxy = WebViewProxy.parse('proxy.example.com:8080')!;

  setUp(() {
    final previous = InAppWebViewPlatform.instance;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    _proxy.settings = null;
    _proxy.clears = 0;
    _proxy.calls.clear();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  });

  test(
    'proxy routes all schemes without direct or local bypass rules',
    () async {
      await configureWebViewProxy(proxy);
      final settings = _proxy.settings!;
      expect(settings.proxyRules.single.url, proxy.uri.toString());
      expect(settings.proxyRules.single.schemeFilter, isNull);
      expect(settings.directs, isEmpty);
      expect(settings.bypassRules, isEmpty);
      expect(settings.removeImplicitRules, isTrue);
      expect(settings.reverseBypassEnabled, isFalse);
      expect(_proxy.clears, 0);
    },
  );

  for (final feature in [
    WebViewFeature.PROXY_OVERRIDE,
    WebViewFeature.DOCUMENT_START_SCRIPT,
  ]) {
    test('unsupported $feature rejects proxy startup', () async {
      platform.unsupported.add(feature);
      await expectLater(
        configureWebViewProxy(proxy),
        throwsA(
          isA<PlatformException>().having(
            (error) => error.code,
            'code',
            'proxy_unsupported',
          ),
        ),
      );
      expect(_proxy.settings, isNull);
      expect(_proxy.clears, 0);
    });
  }

  test(
    'explicit direct mode can clear a proxy without document-start support',
    () async {
      platform.unsupported.add(WebViewFeature.DOCUMENT_START_SCRIPT);
      await configureWebViewProxy(null);
      expect(_proxy.settings, isNull);
      expect(_proxy.clears, 1);
    },
  );

  test(
    'temporary probe restores original override before queued configuration changes',
    () async {
      final original = WebViewProxy.parse('original.example:8080')!;
      final next = WebViewProxy.parse('next.example:8080')!;
      await configureWebViewProxy(original);
      final gate = Completer<void>();
      final temporary = withTemporaryWebViewProxy(proxy, () => gate.future);
      final change = configureWebViewProxy(next);
      await Future<void>.delayed(Duration.zero);
      expect(_proxy.calls, [original.uri.toString(), proxy.uri.toString()]);
      gate.complete();
      await temporary;
      await change;
      expect(_proxy.calls, [
        original.uri.toString(),
        proxy.uri.toString(),
        original.uri.toString(),
        next.uri.toString(),
      ]);
    },
  );

  test(
    'failed probe restores proxy and cancelled queue entries do not change it',
    () async {
      await configureWebViewProxy(null);
      await expectLater(
        withTemporaryWebViewProxy<void>(proxy, () async {
          throw const FormatException('API failed');
        }),
        throwsFormatException,
      );
      expect(_proxy.calls, ['direct', proxy.uri.toString(), 'direct']);
      _proxy.calls.clear();
      await expectLater(
        withTemporaryWebViewProxy<void>(
          proxy,
          () async => fail('Cancelled probe must not run'),
          isCancelled: () => true,
        ),
        throwsFormatException,
      );
      expect(_proxy.calls, isEmpty);
      await configureWebViewProxy(null);
      expect(_proxy.calls, ['direct']);
    },
  );
}
