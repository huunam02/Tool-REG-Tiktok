import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/controller/home_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/webview_privacy.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_proxy_store.dart';
import 'support/test_proxy_ip_platform.dart';

class _Platform extends TestProxyIpPlatform {
  static bool proxyApplied = false;
  @override
  PlatformWebViewFeature createPlatformWebViewFeatureStatic() =>
      _Features(const PlatformWebViewFeatureCreationParams());
  @override
  PlatformProxyController createPlatformProxyController(
    PlatformProxyControllerCreationParams params,
  ) => _Proxy(params, () => proxyApplied = true);
}

class _Features extends PlatformWebViewFeature {
  _Features(super.params) : super.implementation();
  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async => true;
}

class _Proxy extends PlatformProxyController {
  _Proxy(super.params, this.applied) : super.implementation();
  final void Function() applied;
  @override
  Future<void> setProxyOverride({required ProxySettings settings}) async =>
      applied();
  @override
  Future<void> clearProxyOverride() async {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const identityChannel = MethodChannel('test_tiktok/webview_identity');
  const response =
      '{"success":true,"ip":"82.23.203.216","timezone":{"id":"America/New_York"}}';
  late _Platform platform;
  late HomeController home;
  setUp(() async {
    final previous = InAppWebViewPlatform.instance;
    platform = _Platform();
    _Platform.proxyApplied = false;
    InAppWebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    messenger.setMockMethodCallHandler(identityChannel, (_) async => 'agent');
    final store = MemoryProxyStore()
      ..current = WebViewProxy.parse('proxy.example:8080')
      ..currentAccount = const AccountCredentials(
        email: 'test@example.com',
        password: 'test',
        mailboxPassword: 'test',
      );
    home = HomeController(
      initialUserAgent: 'agent',
      initialOtpSettings: const OtpApiSettings(
        url: 'https://otp.example/api',
        token: 'test',
      ),
      store: store,
    );
    home.onInit();
    await Future<void>.delayed(Duration.zero);
    addTearDown(() {
      home.onClose();
      debugDefaultTargetPlatformOverride = null;
      if (previous != null) InAppWebViewPlatform.instance = previous;
      messenger.setMockMethodCallHandler(identityChannel, null);
    });
  });

  for (final action in TikTokLaunchAction.values) {
    test(
      '$action passes proxy timezone to WebView before navigation',
      () async {
        var navigated = false;
        final opening = home.openTikTok(action, (
          configuration,
          actualAction,
        ) async {
          expect(configuration.webViewTimeZone, 'America/New_York');
          expect(
            platform.probes.single.params.initialSettings!.userAgent,
            isNull,
          );
          expect(
            platform.probes.single.params.initialUserScripts!.any(
              (script) => script.source == disableWebRtcScript,
            ),
            isTrue,
          );
          expect(actualAction, action);
          navigated = true;
        });
        await Future<void>.delayed(Duration.zero);
        expect(_Platform.proxyApplied, isTrue);
        expect(navigated, isFalse);
        platform.probes.single.loaded(response);
        await opening;
        expect(navigated, isTrue);
        expect(home.opening, isFalse);
      },
    );
  }

  test('API failure stops page navigation and reports an error', () async {
    var navigated = false;
    final messages = <String>[];
    home.onNotice = (notice) => messages.add(notice.message);
    final opening = home.openTikTok(
      TikTokLaunchAction.browse,
      (_, _) async => navigated = true,
    );
    await Future<void>.delayed(Duration.zero);
    platform.probes.single.loaded('{"success":false}');
    await opening;
    expect(navigated, isFalse);
    expect(messages.single, contains('múi giờ'));
    expect(home.opening, isFalse);
  });

  test('saved timezone is used without requesting the API again', () async {
    home.currentProxy = home.currentProxy!.copyWith(
      timeZoneId: 'Europe/Berlin',
    );
    String? actual;
    await home.openTikTok(TikTokLaunchAction.browse, (configuration, _) async {
      actual = configuration.webViewTimeZone;
    });
    expect(actual, 'Europe/Berlin');
    expect(platform.probes, isEmpty);
    expect(home.currentProxy!.timeZoneId, 'Europe/Berlin');
  });

  test(
    'old active configuration caches detected timezone for later launches',
    () async {
      final store = home.store as MemoryProxyStore;
      final id = await store.save(
        name: 'old',
        proxy: store.current,
        userAgent: 'agent',
      );
      await store.useSaved(id);
      await home.restoreProxy();
      final first = home.openTikTok(TikTokLaunchAction.browse, (_, _) async {});
      await Future<void>.delayed(Duration.zero);
      platform.probes.single.loaded(response);
      await first;
      expect((await store.getCurrentProfile())!.timeZoneId, 'America/New_York');
      await home.restoreProxy();
      await home.openTikTok(TikTokLaunchAction.browse, (
        configuration,
        _,
      ) async {
        expect(configuration.webViewTimeZone, 'America/New_York');
        expect(
          platform.probes.single.params.initialUserScripts!.any(
            (script) => script.source == disableWebRtcScript,
          ),
          isTrue,
        );
      });
      expect(platform.probes, hasLength(1));
    },
  );

  test(
    'switching proxy queries again; direct mode does not retain proxy timezone',
    () async {
      final zones = <String?>[];
      Future<void> open(String apiResponse) async {
        final pending = home.openTikTok(TikTokLaunchAction.browse, (
          configuration,
          _,
        ) async {
          zones.add(configuration.webViewTimeZone);
        });
        await Future<void>.delayed(Duration.zero);
        platform.probes.last.loaded(apiResponse);
        await pending;
      }

      await open(response);
      home.currentProxy = ProxyProfile(
        proxy: WebViewProxy.parse('other.example:8080')!,
        userAgent: 'agent',
        hasBeenUsed: true,
      );
      await open(response.replaceAll('America/New_York', 'Asia/Tokyo'));
      expect(platform.probes, hasLength(2));
      home.currentProxy = null;
      await home.openTikTok(TikTokLaunchAction.browse, (
        configuration,
        _,
      ) async {
        zones.add(configuration.webViewTimeZone);
      });
      expect(zones, ['America/New_York', 'Asia/Tokyo', null]);
      expect(platform.probes, hasLength(2));
    },
  );
}
