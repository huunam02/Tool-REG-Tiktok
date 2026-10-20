import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/proxy_store.dart';
import 'package:test_tiktok/core/webview_privacy.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_proxy_store.dart';
import 'support/test_proxy_ip_platform.dart';

class _Platform extends TestProxyIpPlatform {
  static bool proxyApplied = false;
  static final appliedProxies = <String>[];
  @override
  PlatformWebViewFeature createPlatformWebViewFeatureStatic() =>
      _Features(const PlatformWebViewFeatureCreationParams());
  @override
  PlatformProxyController createPlatformProxyController(
    PlatformProxyControllerCreationParams params,
  ) => _Proxy(params, (settings) {
    proxyApplied = true;
    appliedProxies.add(settings.proxyRules.single.url);
  });
}

class _Features extends PlatformWebViewFeature {
  _Features(super.params) : super.implementation();
  @override
  Future<bool> isFeatureSupported(WebViewFeature feature) async => true;
}

class _Proxy extends PlatformProxyController {
  _Proxy(super.params, this.applied) : super.implementation();
  final void Function(ProxySettings) applied;
  @override
  Future<void> setProxyOverride({required ProxySettings settings}) async =>
      applied(settings);
  @override
  // Going back to the device's own network is recorded as `direct`.
  Future<void> clearProxyOverride() async =>
      _Platform.appliedProxies.add('direct');
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
  var sessionClears = 0;
  setUp(() async {
    final previous = InAppWebViewPlatform.instance;
    platform = _Platform();
    _Platform.proxyApplied = false;
    _Platform.appliedProxies.clear();
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
      // Auto runs clear the WebView session; there is none in these tests.
      clearSession: () async => sessionClears++,
      initialUserAgent: 'agent',
      initialOtpSettings: const OtpApiSettings(url: 'https://otp.example/api'),
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

  test(
    'returning after signup refreshes status and changes the account action',
    () async {
      final id = await home.store.save(
        name: 'Signup',
        proxy: null,
        account: const AccountCredentials(
          email: 'signup@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      );
      await home.store.useSaved(id);
      await home.restoreProxy();
      expect(home.accountAction, TikTokLaunchAction.signup);
      await home.openTikTok(TikTokLaunchAction.signup, (
        configuration,
        _,
      ) async {
        expect(configuration.configurationId, id);
        await home.store.markRegistered(id, configuration.signupEmail);
      });
      expect(home.currentProxy!.statusAccount, AccountStatus.registered);
      expect(home.accountAction, TikTokLaunchAction.login);
    },
  );

  test('signup and nurture use the selected configuration\'s nurture '
      'settings', () async {
    const custom = NurtureSettings(
      likePercent: 45,
      commentPercent: 5,
      longWatchPercent: 70,
      minMinutes: 10,
      maxMinutes: 20,
    );
    Future<int> save(String email, NurtureSettings? settings) =>
        home.store.save(
          name: email,
          proxy: WebViewProxy.parse(
            '${email.split('@').first}.proxy.example:8080',
          ),
          timeZoneId: 'Europe/Berlin',
          account: AccountCredentials(
            email: email,
            password: 'password',
            mailboxPassword: 'mail',
          ),
          nurtureSettings: settings,
        );
    final plain = await save('plain@example.com', null);
    final tuned = await save('tuned@example.com', custom);
    final seen = <String, NurtureSettings>{};
    for (final (id, action) in [
      (tuned, TikTokLaunchAction.signup),
      (tuned, TikTokLaunchAction.login),
      (plain, TikTokLaunchAction.login),
    ]) {
      await home.store.useSaved(id);
      await home.restoreProxy();
      await home.openTikTok(action, (configuration, _) async {
        seen['${configuration.loginUsername} $action'] =
            configuration.nurtureSettings;
      });
    }
    expect(seen, {
      'tuned@example.com ${TikTokLaunchAction.signup}': custom,
      'tuned@example.com ${TikTokLaunchAction.login}': custom,
      'plain@example.com ${TikTokLaunchAction.login}': NurtureSettings.defaults,
    });
  });

  test('Kiểm tra IP loads the configuration in a fresh session and keeps '
      'it unused', () async {
    final other = await home.store.save(
      name: 'Other',
      proxy: null,
      account: const AccountCredentials(
        email: 'other@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      ),
    );
    await home.store.useSaved(other);
    await home.restoreProxy();
    final id = await home.store.save(
      name: 'Checked',
      proxy: WebViewProxy.parse('checked.example:8080'),
      // Known zone: no lookup through the (unreachable) test proxy.
      timeZoneId: 'Europe/Berlin',
      account: const AccountCredentials(
        email: 'checked@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      ),
      gpuProfileId: 'galaxy-s23',
    );
    final entry = (await home.store.list()).singleWhere((e) => e.id == id);
    expect(entry.hasBeenUsed, isFalse);
    final clearsBefore = sessionClears;
    AppConfiguration? opened;
    await home.checkConfiguration(entry, (configuration) async {
      opened = configuration;
    });
    expect(sessionClears, clearsBefore + 1);
    expect(opened!.configurationId, id);
    expect(opened!.proxy!.uri.host, 'checked.example');
    expect(opened!.gpuProfile.id, 'galaxy-s23');
    expect(opened!.webViewTimeZone, 'Europe/Berlin');
    expect(_Platform.appliedProxies.last, contains('checked.example'));
    expect(home.currentProxy!.configurationId, id);
    final saved = (await home.store.list()).singleWhere((e) => e.id == id);
    expect(saved.hasBeenUsed, isFalse);
    // Quản lý cấu hình is open meanwhile; the check still runs.
    home.managingProxies = true;
    opened = null;
    await home.checkConfiguration(saved, (configuration) async {
      opened = configuration;
    });
    expect(opened, isNotNull);
    home.managingProxies = false;
  });

  test('opening TikTok uses the selected configuration\'s phone GPU', () async {
    final seen = <String>[];
    for (final gpu in ['galaxy-s23', 'pixel-7']) {
      final id = await home.store.save(
        name: gpu,
        proxy: WebViewProxy.parse('$gpu.proxy.example:8080'),
        timeZoneId: 'Europe/Berlin',
        account: AccountCredentials(
          email: '$gpu@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
        gpuProfileId: gpu,
      );
      await home.store.useSaved(id);
      await home.restoreProxy();
      await home.openTikTok(TikTokLaunchAction.login, (configuration, _) async {
        seen.add(configuration.gpuProfile.id);
      });
    }
    expect(seen, ['galaxy-s23', 'pixel-7']);
  });

  test('Đăng ký, Nuôi toàn bộ and Đăng ký lại (Cấu hình lỗi) all run with '
      'each configuration\'s nurture settings', () async {
    const custom = NurtureSettings(
      likePercent: 45,
      commentPercent: 5,
      longWatchPercent: 70,
      minMinutes: 10,
      maxMinutes: 20,
    );
    Future<int> save(String email, AccountStatus status) => home.store.save(
      name: email,
      proxy: WebViewProxy.parse('${email.split('@').first}.proxy.example:8080'),
      timeZoneId: 'Europe/Berlin',
      account: AccountCredentials(
        email: email,
        password: 'password',
        mailboxPassword: 'mail',
      ),
      statusAccount: status,
      nurtureAfterSignup: true,
      nurtureSettings: custom,
    );
    await save('new@example.com', AccountStatus.unregistered);
    await save('registered@example.com', AccountStatus.registered);
    final failed = await save('failed@example.com', AccountStatus.unregistered);
    await home.store.recordSignupFailure(
      failed,
      'failed@example.com',
      message: 'CAPTCHA',
    );
    final seen = <AutoRunMode, List<String>>{};
    for (final mode in AutoRunMode.values) {
      await home.startAutoRun(mode, (configuration, action) async {
        expect(configuration.nurtureSettings, custom);
        expect(configuration.nurtureAfterSignup, isTrue);
        (seen[mode] ??= []).add('${configuration.loginUsername} $action');
        return TikTokFlowResult.failed;
      });
    }
    expect(seen, {
      AutoRunMode.signup: ['new@example.com ${TikTokLaunchAction.signup}'],
      AutoRunMode.nurture: [
        'registered@example.com ${TikTokLaunchAction.login}',
      ],
      AutoRunMode.retryFailed: [
        'failed@example.com ${TikTokLaunchAction.signup}',
      ],
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

  // Đăng ký, Nuôi and Đăng ký lại share one run loop; each is checked.
  for (final mode in AutoRunMode.values) {
    test(
      '$mode clears the session and loads each configuration before its account',
      () async {
        final store = MemoryProxyStore();
        Future<int> save(String name, String? proxy, String zone) => store.save(
          name: name,
          proxy: proxy == null ? null : WebViewProxy.parse(proxy),
          account: AccountCredentials(
            email: '$name@example.com',
            password: 'password',
            mailboxPassword: 'mail',
          ),
          statusAccount: mode == AutoRunMode.nurture
              ? AccountStatus.registered
              : AccountStatus.unregistered,
          timeZoneId: zone,
        );
        final a = await save('a', 'a.example:1111', 'Europe/Warsaw');
        final b = await save('b', 'b.example:2222', 'America/Chicago');
        // No proxy: use the device network and clear the previous override.
        final c = await save('c', null, '');
        if (mode == AutoRunMode.retryFailed) {
          for (final (id, name) in [(a, 'a'), (b, 'b'), (c, 'c')]) {
            await store.recordSignupFailure(
              id,
              '$name@example.com',
              message: 'x',
            );
          }
        }
        await store.useSaved(a);
        // Each read jumps a minute, so the pause between accounts is skipped.
        var clock = DateTime(2026);
        // Proxies applied so far, sampled when a session is cleared.
        final clearedAt = <int>[];
        final run = HomeController(
          initialUserAgent: 'agent',
          initialOtpSettings: const OtpApiSettings(
            url: 'https://otp.example/api',
          ),
          store: store,
          now: () => clock = clock.add(const Duration(minutes: 1)),
          readLoginSession: () async => false,
          clearSession: () async =>
              clearedAt.add(_Platform.appliedProxies.length),
        );
        run.onInit();
        addTearDown(run.onClose);
        await run.restoreProxy();
        final opened = <(int?, String, String?, String)>[];
        final openedAt = <int>[];
        await run.startAutoRun(mode, (configuration, _) async {
          openedAt.add(_Platform.appliedProxies.length);
          opened.add((
            configuration.configurationId,
            configuration.loginUsername,
            configuration.webViewTimeZone,
            // The proxy in force when this account's page opens.
            _Platform.appliedProxies.last,
          ));
          return TikTokFlowResult.failed;
        });
        expect(opened, [
          (a, 'a@example.com', 'Europe/Warsaw', 'http://a.example:1111'),
          (c, 'c@example.com', null, 'direct'),
          (b, 'b@example.com', 'America/Chicago', 'http://b.example:2222'),
        ]);
        // Every account: clear the session, then apply its proxy, then open.
        expect(clearedAt, hasLength(3));
        expect(run.autoRunFailed, 3);
        for (var i = 0; i < 3; i++) {
          expect(clearedAt[i], lessThan(openedAt[i]));
          if (i > 0) {
            expect(clearedAt[i], greaterThanOrEqualTo(openedAt[i - 1]));
          }
        }
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
