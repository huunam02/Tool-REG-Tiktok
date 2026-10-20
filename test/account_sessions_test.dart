import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';
import 'support/memory_proxy_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/account_sessions.dart';

class _Platform extends InAppWebViewPlatform {
  List<Cookie> cookies = [];
  bool rejectRestore = false;
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _View(params);
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params, this);
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.owner) : super.implementation();
  final _Platform owner;
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async => owner.cookies;
  @override
  Future<bool> setCookie({
    required WebUri url,
    required String name,
    required String value,
    String path = '/',
    String? domain,
    int? expiresDate,
    int? maxAge,
    bool? isSecure,
    bool? isHttpOnly,
    HTTPCookieSameSitePolicy? sameSite,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async {
    if (owner.rejectRestore) return false;
    owner.cookies.add(
      Cookie(
        name: name,
        value: value,
        path: path,
        domain: domain,
        expiresDate: expiresDate,
        isSecure: isSecure,
        isHttpOnly: isHttpOnly,
        sameSite: sameSite,
      ),
    );
    return true;
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
  Future<void> clear() async => platform.cookies = [];

  test(
    'A → B → A restores only the selected configuration, including HttpOnly',
    () async {
      platform.cookies = [
        Cookie(
          name: 'sessionid',
          value: 'A',
          domain: '.tiktok.com',
          path: '/',
          isHttpOnly: true,
          isSecure: true,
        ),
      ];
      await AccountSessions.save(1, 'a@example.com');
      await AccountSessions.activate(2, 'b@example.com', clear: clear);
      expect(platform.cookies, isEmpty);
      platform.cookies = [Cookie(name: 'sessionid', value: 'B')];
      await AccountSessions.save(2, 'b@example.com');
      await AccountSessions.activate(1, 'a@example.com', clear: clear);
      expect(platform.cookies.single.value, 'A');
      expect(platform.cookies.single.isHttpOnly, isTrue);
      expect(platform.cookies.single.domain, '.tiktok.com');
      await AccountSessions.activate(2, 'b@example.com', clear: clear);
      expect(platform.cookies.single.value, 'B');
    },
  );

  test(
    'different configurations never share a jar even with the same email',
    () async {
      platform.cookies = [Cookie(name: 'sessionid', value: 'first')];
      await AccountSessions.save(1, 'same@example.com');
      await AccountSessions.activate(2, 'same@example.com', clear: clear);
      expect(platform.cookies, isEmpty);
      platform.cookies = [Cookie(name: 'sessionid', value: 'second')];
      await AccountSessions.save(2, 'same@example.com');
      await AccountSessions.activate(1, 'same@example.com', clear: clear);
      expect(platform.cookies.single.value, 'first');
    },
  );

  test(
    'restart with an empty native store restores the persisted session',
    () async {
      platform.cookies = [Cookie(name: 'sessionid', value: 'saved')];
      await AccountSessions.save(1, 'a');
      await clear();
      await (await SharedPreferences.getInstance()).reload();
      await AccountSessions.activate(1, 'a', clear: clear);
      expect(platform.cookies.single.value, 'saved');
    },
  );

  test(
    'expired cookies and another email on the same ID are not restored',
    () async {
      platform.cookies = [
        Cookie(name: 'sessionid', value: 'expired', expiresDate: 1),
      ];
      await AccountSessions.save(1, 'a');
      await AccountSessions.activate(2, 'b', clear: clear);
      await AccountSessions.activate(1, 'a', clear: clear);
      expect(platform.cookies, isEmpty);
      platform.cookies = [Cookie(name: 'sessionid', value: 'a')];
      await AccountSessions.save(1, 'a');
      await AccountSessions.activate(1, 'replacement', clear: clear);
      expect(platform.cookies, isEmpty);
    },
  );

  test('failed switch cannot overwrite the previous account jar', () async {
    platform.cookies = [Cookie(name: 'sessionid', value: 'A')];
    await AccountSessions.save(1, 'a');
    await AccountSessions.activate(2, 'b', clear: clear);
    platform.cookies = [Cookie(name: 'sessionid', value: 'B')];
    await AccountSessions.save(2, 'b');
    platform.rejectRestore = true;
    await expectLater(
      AccountSessions.activate(1, 'a', clear: clear),
      throwsStateError,
    );
    await AccountSessions.save(2, 'b');
    platform.rejectRestore = false;
    await AccountSessions.activate(2, 'b', clear: clear);
    expect(platform.cookies.single.value, 'B');
  });

  testWidgets('Nuôi button mounts exactly that account’s proxy and cookies', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.binding.setSurfaceSize(const Size(900, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    const channel = MethodChannel('test_tiktok/webview_proxy');
    final proxyCalls = <Map<dynamic, dynamic>>[];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(channel, (
      call,
    ) async {
      proxyCalls.add(call.arguments as Map);
      return null;
    });
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        channel,
        null,
      ),
    );
    final store = MemoryProxyStore();
    final ids = <int>[];
    const names = ['a', 'b', 'direct'];
    for (final name in names) {
      final id = await store.save(
        name: name,
        proxy: name == 'direct'
            ? null
            : WebViewProxy.parse(
                '$name.proxy.example:8080',
                username: name,
                password: '$name-secret',
              ),
        account: AccountCredentials(
          email: '$name@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
        statusAccount: AccountStatus.registered,
      );
      ids.add(id);
      await AccountSessions.activate(id, '$name@example.com', clear: clear);
      platform.cookies = [Cookie(name: 'sessionid', value: 'session-$name')];
      await AccountSessions.save(id, '$name@example.com');
    }
    await store.useSaved(ids.last);
    await store.setCurrentAccountLoggedIn(ids.last, 'direct@example.com', true);
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(
          userAgent: 'test-agent',
          proxyStore: store,
          clearSession: clear,
          initialOtpSettings: const OtpApiSettings(
            url: 'https://otp.example.com',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('nurtureTab')));
    await tester.pumpAndSettle();
    for (var i = 0; i < ids.length; i++) {
      final name = names[i];
      final direct = name == 'direct';
      final button = find.byKey(Key('nurtureOne-${ids[i]}'));
      await tester.ensureVisible(button);
      await tester.tap(button);
      await tester.pumpAndSettle();
      final page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, ids[i]);
      expect(page.configuration.loginUsername, '$name@example.com');
      expect(
        page.configuration.proxy?.uri.host,
        direct ? null : '$name.proxy.example',
      );
      expect(page.configuration.proxy?.username, direct ? null : name);
      expect(platform.cookies.single.value, 'session-$name');
      expect(proxyCalls.last['host'], direct ? null : '$name.proxy.example');
      expect(proxyCalls.last['username'], direct ? null : name);
      expect(page.logoutAfterNurture, isFalse);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  test('fresh signup and deletion discard saved cookies', () async {
    platform.cookies = [Cookie(name: 'sessionid', value: 'old')];
    await AccountSessions.save(1, 'a');
    await AccountSessions.activate(1, 'a', clear: clear, fresh: true);
    expect(platform.cookies, isEmpty);
    await AccountSessions.activate(2, 'b', clear: clear);
    await AccountSessions.activate(1, 'a', clear: clear);
    expect(platform.cookies, isEmpty);
    platform.cookies = [Cookie(name: 'sessionid', value: 'new')];
    await AccountSessions.save(1, 'a');
    await AccountSessions.delete(1);
    await AccountSessions.activate(2, 'b', clear: clear);
    await AccountSessions.activate(1, 'a', clear: clear);
    expect(platform.cookies, isEmpty);
  });
}
