import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/home_controller.dart';
import 'package:test_tiktok/core/app_session.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_proxy_store.dart';

class _Platform extends InAppWebViewPlatform {
  List<Cookie> cookies = [];
  bool fail = false;

  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params, this);
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.owner) : super.implementation();
  final _Platform owner;

  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    expect(url.toString(), 'https://www.tiktok.com/');
    if (owner.fail) throw StateError('Cookie store unavailable');
    return owner.cookies;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    final previous = InAppWebViewPlatform.instance;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  });

  test('retained login cookies must have a value and be unexpired', () async {
    final now = DateTime(2026, 10, 16);
    for (final name in ['sid_tt', 'sessionid', 'sessionid_ss']) {
      platform.cookies = [Cookie(name: name, value: 'test-session')];
      expect(await hasTikTokLoginSession(now: now), isTrue);
      platform.cookies.single.expiresDate = now.millisecondsSinceEpoch;
      expect(await hasTikTokLoginSession(now: now), isFalse);
      platform.cookies.single.expiresDate = now
          .add(const Duration(minutes: 1))
          .millisecondsSinceEpoch;
      expect(await hasTikTokLoginSession(now: now), isTrue);
      platform.cookies.single.value = '';
      expect(await hasTikTokLoginSession(now: now), isFalse);
    }
    platform.cookies = [Cookie(name: 'ttwid', value: 'analytics')];
    expect(await hasTikTokLoginSession(now: now), isFalse);
    platform.fail = true;
    expect(await hasTikTokLoginSession(now: now), isFalse);
  });

  testWidgets(
    'Home derives its account button from retained login, including after restart',
    (tester) async {
      final store = MemoryProxyStore();
      final id = await store.save(
        name: 'Current account',
        proxy: null,
        account: const AccountCredentials(
          email: 'current@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(id);
      HomeController createHome() => HomeController(
        initialUserAgent: 'agent',
        initialOtpSettings: const OtpApiSettings(url: ''),
        store: store,
      )..onInit();
      var home = createHome();
      await tester.pump();
      expect(home.accountAction, TikTokLaunchAction.login);
      platform.cookies = [Cookie(name: 'sid_tt', value: 'retained-session')];
      await store.setCurrentAccountLoggedIn(id, 'current@example.com', true);
      await home.restoreProxy();
      expect(home.accountAction, TikTokLaunchAction.browse);
      expect(home.accountAction, TikTokLaunchAction.browse);
      home.onDelete();
      home = createHome();
      addTearDown(() => home.onDelete());
      await home.restoreProxy();
      expect(home.accountAction, TikTokLaunchAction.browse);
      final otherId = await store.save(
        name: 'Other account',
        proxy: null,
        account: const AccountCredentials(
          email: 'other@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
        statusAccount: AccountStatus.registered,
      );
      // Even if the native cookie store still contains the old session,
      // choosing another configuration invalidates its login confirmation.
      await store.useSaved(otherId);
      await home.restoreProxy();
      expect(home.hasCurrentAccountSession, isFalse);
      expect(home.accountAction, TikTokLaunchAction.login);
      await home.refreshCurrentAccountSession();
      expect(home.hasCurrentAccountSession, isFalse);
      home.onDelete();
      home = createHome();
      await home.restoreProxy();
      expect(home.hasCurrentAccountSession, isFalse);
      expect(
        await store.setCurrentAccountLoggedIn(id, 'current@example.com', true),
        isFalse,
      );
      await home.refreshCurrentAccountSession();
      expect(home.hasCurrentAccountSession, isFalse);
      await store.setCurrentAccountLoggedIn(otherId, 'other@example.com', true);
      await home.refreshCurrentAccountSession();
      expect(home.accountAction, TikTokLaunchAction.browse);
      platform.cookies.clear();
      home.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(home.accountAction, TikTokLaunchAction.login);
      expect(home.accountAction, TikTokLaunchAction.login);
      await store.setCurrent(null);
      platform.cookies = [Cookie(name: 'sid_tt', value: 'unbound-session')];
      await home.restoreProxy();
      expect(home.hasCurrentAccountSession, isFalse);
      home.onDelete();
      await tester.pump();
    },
  );
}
