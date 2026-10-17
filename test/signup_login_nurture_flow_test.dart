import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/home_controller.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/otp_settings_store.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_logout_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';

import 'support/memory_proxy_store.dart';

class _BoundaryRandom implements Random {
  _BoundaryRandom(this.maximum);
  final bool maximum;
  @override
  int nextInt(int max) => maximum ? max - 1 : 0;
  @override
  bool nextBool() => maximum;
  @override
  double nextDouble() => maximum ? 0.999 : 0;
}

class _View extends PlatformInAppWebViewController {
  _View()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  String loginResult = 'login-success';
  String signupResult = 'signup-success';
  final logoutResults = ['logout-requested', 'logged-out', 'logged-out'];
  int logoutCalls = 0;
  int watchStarts = 0;
  int watchStops = 0;
  int reloads = 0;
  bool failNextLogoutEvaluation = false;
  Completer<void>? loginStopGate;
  bool stoppingLogin = false;
  @override
  Future<void> reload() async => reloads++;
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}
  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoSignupStepScript)) return signupResult;
    if (source.contains(autoLoginStepScript)) return loginResult;
    if (source.contains('delete window.__flutterAutoLogin;')) {
      stoppingLogin = true;
      await loginStopGate?.future;
      return true;
    }
    if (source.contains(autoLogoutStepScript)) {
      if (failNextLogoutEvaluation) {
        failNextLogoutEvaluation = false;
        throw StateError('Page context replaced during logout');
      }
      logoutCalls++;
      return logoutResults.length > 1
          ? logoutResults.removeAt(0)
          : logoutResults.single;
    }
    if (source.contains(autoWatchStartScript)) watchStarts++;
    if (source == autoWatchStopScript) watchStops++;
    return true;
  }
}

class _Platform extends InAppWebViewPlatform {
  bool loggedIn = false;
  @override
  PlatformCookieManager createPlatformCookieManager(
    PlatformCookieManagerCreationParams params,
  ) => _Cookies(params, this);

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _WebViewWidget(params);
}

class _Cookies extends PlatformCookieManager {
  _Cookies(super.params, this.owner) : super.implementation();
  final _Platform owner;
  @override
  Future<List<Cookie>> getCookies({
    required WebUri url,
    PlatformInAppWebViewController? iosBelow11WebViewController,
    PlatformInAppWebViewController? webViewController,
  }) async =>
      owner.loggedIn ? [Cookie(name: 'sid_tt', value: 'test-session')] : [];
}

class _WebViewWidget extends PlatformInAppWebViewWidget {
  _WebViewWidget(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _Session {
  _Session(this.tester, {bool maximum = false})
    : random = _BoundaryRandom(maximum);
  final WidgetTester tester;
  final Random random;
  final store = MemoryProxyStore();
  final view = _View();
  final results = <TikTokFlowResult>[];
  final notices = <String>[];
  late AppConfiguration configuration;
  late TikTokController logic;
  late HomeController home;

  Future<void> init() async {
    const account = AccountCredentials(
      email: 'person@example.com',
      password: 'password',
      mailboxPassword: 'mail',
    );
    final id = await store.save(name: 'Account', proxy: null, account: account);
    await store.useSaved(id);
    configuration = AppConfiguration(
      configurationId: id,
      userAgent: 'agent',
      signupEmail: account.email,
      signupPassword: account.password,
      signupMailboxPassword: account.mailboxPassword,
      loginUsername: account.email,
      loginPassword: account.password,
      loginMailboxPassword: account.mailboxPassword,
      comments: ['Test comment'],
    );
    logic = TikTokController(
      configuration: configuration,
      proxyStore: store,
      useAccessibility: false,
      now: tester.binding.clock.now,
      workflowRandom: random,
      onFlowFinished: results.add,
    )..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: view,
    );
    logic.onNotice = (notice) => notices.add(notice.message);
    home = HomeController(
      initialUserAgent: 'agent',
      initialOtpSettings: const OtpApiSettings.defaults(),
      store: store,
      now: tester.binding.clock.now,
      workflowRandom: random,
    )..onInit();
    home.onNotice = (notice) => notices.add(notice.message);
    addTearDown(() {
      logic.onDelete();
      home.onDelete();
    });
    await tester.pump();
  }

  Future<void> signup() async {
    final run = logic.autoSignup();
    await tester.pump();
    for (var i = 0; i < 11 && logic.autoSignupBusy; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await run;
  }

  Future<void> login() async {
    final run = logic.autoLogin();
    await tester.pump();
    for (var i = 0; i < 11 && logic.autoLoginBusy; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await run;
  }

  Future<void> reachLogout() async {
    final wait = logic.signupLogoutAt!.difference(tester.binding.clock.now());
    await tester.pump(wait);
    await tester.pump();
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  for (final result in ['login-success', 'already-logged-in', 'login-error']) {
    testWidgets('$result persists login status before cleanup and nurturing', (
      tester,
    ) async {
      final session = _Session(tester);
      await session.init();
      final gate = Completer<void>();
      addTearDown(() {
        if (!gate.isCompleted) gate.complete();
      });
      session.view.loginResult = result;
      session.view.loginStopGate = gate;
      expect(await session.store.canReuseCurrentAccountSession(), isFalse);
      final run = session.logic.autoLogin();
      await tester.pump();
      for (var tick = 0; tick < 11 && !session.view.stoppingLogin; tick++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(session.view.stoppingLogin, isTrue);
      expect(
        await session.store.canReuseCurrentAccountSession(),
        result != 'login-error',
      );
      expect(session.logic.loginConfirmed, result != 'login-error');
      expect(session.view.watchStarts, 0);
      gate.complete();
      await tester.pump();
      await run;
      expect(session.logic.autoWatchEnabled, result != 'login-error');
      session.logic.onDelete();
      session.home.onDelete();
      await tester.pump();
    });
  }

  testWidgets(
    'routes through Home between signup and login, then reports nurture completion',
    (tester) async {
      final previous = InAppWebViewPlatform.instance;
      final platform = _Platform();
      InAppWebViewPlatform.instance = platform;
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final messenger = tester.binding.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (_) async => null,
      );
      addTearDown(() {
        if (previous != null) InAppWebViewPlatform.instance = previous;
        debugDefaultTargetPlatformOverride = null;
        messenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'),
          null,
        );
      });
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      final id = await store.save(
        name: 'Account',
        proxy: null,
        account: const AccountCredentials(
          email: 'person@example.com',
          password: 'password',
          mailboxPassword: 'mail',
        ),
      );
      await store.useSaved(id);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('runAccountAction')));
      await tester.pumpAndSettle();
      TikTokController currentLogic() => tester
          .state<GetBuilderState<TikTokController>>(
            find.byType(GetBuilder<TikTokController>),
          )
          .controller!;
      final signup = currentLogic();
      final signupView = _View();
      signup.webViewController = InAppWebViewController.fromPlatform(
        platform: signupView,
      );
      final registration = signup.autoSignup();
      await tester.pump();
      for (var i = 0; i < 11 && signup.autoSignupBusy; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await registration;
      expect(signup.waitingToLogout, isTrue);
      // Timer durations are covered below with an injected clock. Exercise the
      // production route callbacks through the overdue/resume path here.
      await tester.pump(const Duration(minutes: 4));
      signup.signupLogoutAt = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      signup.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      expect(find.byKey(const Key('waitingForAutoLogin')), findsOneWidget);
      final home = tester
          .state<GetBuilderState<HomeController>>(
            find.byType(GetBuilder<HomeController>),
          )
          .controller!;
      // Trigger the same deadline/resume path, retaining the production route callback.
      await tester.pump(const Duration(minutes: 3));
      home.autoLoginStartsAt = DateTime.now().subtract(
        const Duration(seconds: 1),
      );
      home.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pumpAndSettle();
      final loginPage = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(loginPage.launchAction, TikTokLaunchAction.login);
      expect(loginPage.configuration.configurationId, id);
      final login = currentLogic();
      final loginView = _View();
      login.webViewController = InAppWebViewController.fromPlatform(
        platform: loginView,
      );
      final authentication = login.autoLogin();
      await tester.pump();
      for (var i = 0; i < 11 && login.autoLoginBusy; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await authentication;
      platform.loggedIn = true;
      expect(login.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      expect(
        find.text('Đã nuôi xong. Tài khoản vẫn đang đăng nhập.'),
        findsOneWidget,
      );
      expect(loginView.logoutCalls, 0);
      expect(home.waitingForAutoLogin, isFalse);
      expect(find.text('Nuôi tiếp Account'), findsOneWidget);
      await tester.tap(find.byKey(const Key('runAccountAction')));
      await tester.pumpAndSettle();
      final continuedPage = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(continuedPage.launchAction, TikTokLaunchAction.browse);
      expect(continuedPage.startWithNurture, isTrue);
      expect(continuedPage.configuration.configurationId, id);
      expect(continuedPage.configuration.otpApi, isNull);
      final continued = currentLogic();
      final continuedView = _View();
      continued.webViewController = InAppWebViewController.fromPlatform(
        platform: continuedView,
      );
      continued.initialPageLoaded = true;
      continued.mutate(() => continued.loadingProgress = 100);
      await continued.runInitialAction();
      await tester.pump();
      expect(continued.autoWatchEnabled, isTrue);
      expect(continuedView.watchStarts, 1);
      await tester.pump(const Duration(minutes: 10));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      expect(find.text('Nuôi tiếp Account'), findsOneWidget);
      expect(continuedView.logoutCalls, 0);
      // The separate Mở TikTok action remains fully manual, even with cookies.
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TikTokPage>(find.byType(TikTokPage)).startWithNurture,
        isFalse,
      );
      platform.loggedIn = false;
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.text('Nuôi tiếp Account'), findsNothing);
      expect(find.text('Đăng nhập và nuôi Account'), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  for (final maximum in [false, true]) {
    testWidgets(
      'signup waits ${maximum ? 4 : 2} minutes and confirms logout before returning',
      (tester) async {
        final session = _Session(tester, maximum: maximum);
        await session.init();
        await session.signup();
        expect(session.store.currentStatus, AccountStatus.registered);
        final wait = session.logic.signupLogoutAt!.difference(
          tester.binding.clock.now(),
        );
        expect(
          wait,
          greaterThanOrEqualTo(
            Duration(minutes: maximum ? 4 : 2) - const Duration(seconds: 1),
          ),
        );
        expect(wait, lessThanOrEqualTo(Duration(minutes: maximum ? 4 : 2)));
        expect(session.view.watchStarts, 0);
        await tester.pump(wait - const Duration(milliseconds: 1));
        expect(session.view.logoutCalls, 0);
        await tester.pump(const Duration(milliseconds: 1));
        expect(session.results, isEmpty);
        await tester.pump(const Duration(milliseconds: 700));
        expect(session.results, isEmpty);
        await tester.pump(const Duration(milliseconds: 700));
        expect(session.results, [TikTokFlowResult.signupLoggedOut]);
        expect(session.logic.waitingToLogout, isFalse);
        await tester.pump(const Duration(minutes: 15));
        expect(session.view.logoutCalls, 3);
      },
    );
  }

  for (final reason in [
    'cancel',
    'close',
    'background',
    'logout-error',
    'timeout',
  ]) {
    testWidgets(
      'signup handoff handles $reason without an unconfirmed return',
      (tester) async {
        final session = _Session(tester);
        await session.init();
        await session.signup();
        if (reason == 'cancel') session.logic.cancelAutoActions();
        if (reason == 'close') session.logic.onDelete();
        if (reason == 'background') {
          session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
        }
        if (reason == 'logout-error' || reason == 'timeout') {
          session.view.logoutResults
            ..clear()
            ..add(
              reason == 'timeout' ? 'waiting-menu' : 'verification-required',
            );
        }
        await tester.pump(const Duration(minutes: 4));
        await tester.pump(const Duration(seconds: 46));
        expect(session.results, isEmpty);
        if (reason == 'background') {
          expect(session.view.logoutCalls, 0);
          session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 700));
          await tester.pump(const Duration(milliseconds: 700));
          expect(session.results, [TikTokFlowResult.signupLoggedOut]);
        } else if (reason == 'logout-error' || reason == 'timeout') {
          expect(session.logic.waitingToLogout, isFalse);
          expect(
            session.notices.last,
            contains('Chưa xác nhận được đăng xuất'),
          );
        } else {
          expect(session.view.logoutCalls, 0);
        }
      },
    );
  }

  testWidgets(
    'reload retains the signup logout deadline and retries a replaced page context',
    (tester) async {
      final session = _Session(tester);
      await session.init();
      await session.signup();
      final deadline = session.logic.signupLogoutAt;
      session.logic.reloadPage();
      expect(session.view.reloads, 1);
      expect(session.logic.signupLogoutAt, deadline);
      session.view.failNextLogoutEvaluation = true;
      await session.reachLogout();
      expect(session.results, isEmpty);
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(session.results, [TikTokFlowResult.signupLoggedOut]);
    },
  );

  testWidgets(
    'cancelling during logout cannot hand off a late result to Home',
    (tester) async {
      final session = _Session(tester);
      await session.init();
      await session.signup();
      await session.reachLogout();
      expect(session.view.logoutCalls, 1);
      session.logic.cancelAutoActions();
      await tester.pump(const Duration(minutes: 1));
      expect(session.results, isEmpty);
      expect(session.view.logoutCalls, 1);
    },
  );

  for (final maximum in [false, true]) {
    testWidgets(
      'Home waits ${maximum ? 3 : 2} minutes then starts the matching login once',
      (tester) async {
        final session = _Session(tester, maximum: maximum);
        await session.init();
        await session.store.markRegistered(
          session.configuration.configurationId!,
          session.configuration.signupEmail,
        );
        var logins = 0;
        session.home.scheduleLoginAfterSignup(session.configuration, () async {
          logins++;
        });
        final wait = session.home.autoLoginStartsAt!.difference(
          tester.binding.clock.now(),
        );
        expect(wait, Duration(minutes: maximum ? 3 : 2));
        expect(session.home.busy, isTrue);
        await tester.pump(wait - const Duration(milliseconds: 1));
        expect(logins, 0);
        await tester.pump(const Duration(milliseconds: 1));
        await tester.pump();
        expect(logins, 1);
        expect(session.home.waitingForAutoLogin, isFalse);
        await tester.pump(const Duration(minutes: 5));
        expect(logins, 1);
      },
    );
  }

  for (final reason in ['cancel', 'close', 'changed-account', 'background']) {
    testWidgets('Home login schedule handles $reason', (tester) async {
      final session = _Session(tester);
      await session.init();
      await session.store.markRegistered(
        session.configuration.configurationId!,
        session.configuration.signupEmail,
      );
      var logins = 0;
      session.home.scheduleLoginAfterSignup(session.configuration, () async {
        logins++;
      });
      if (reason == 'cancel') session.home.cancelScheduledLogin();
      if (reason == 'close') session.home.onDelete();
      if (reason == 'changed-account') session.store.currentId = 999;
      if (reason == 'background') {
        session.home.didChangeAppLifecycleState(AppLifecycleState.paused);
      }
      await tester.pump(const Duration(minutes: 4));
      expect(logins, 0);
      if (reason == 'background') {
        session.home.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(logins, 1);
      } else {
        expect(session.home.waitingForAutoLogin, isFalse);
      }
    });
  }

  testWidgets(
    'automatic login nurtures for ten minutes then returns without logout',
    (tester) async {
      final session = _Session(tester);
      await session.init();
      await session.login();
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.results, isEmpty);
      await tester.pump(const Duration(minutes: 9, seconds: 58));
      expect(session.results, isEmpty);
      await tester.pump(const Duration(seconds: 2));
      expect(session.results, [TikTokFlowResult.nurtureCompleted]);
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.logic.loginConfirmed, isTrue);
      expect(session.view.logoutCalls, 0);
      await tester.pump(const Duration(minutes: 10));
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await tester.pump();
      expect(session.results, hasLength(1));
    },
  );

  testWidgets('completed nurture returns on resume while preserving login', (
    tester,
  ) async {
    final session = _Session(tester);
    await session.init();
    await session.login();
    session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
    await tester.pump(const Duration(minutes: 11));
    expect(session.results, isEmpty);
    session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    expect(session.results, [TikTokFlowResult.nurtureCompleted]);
    expect(session.logic.loginConfirmed, isTrue);
    expect(session.view.logoutCalls, 0);
  });

  testWidgets('failed automatic login does not nurture or report completion', (
    tester,
  ) async {
    final session = _Session(tester);
    await session.init();
    session.view.loginResult = 'verification-required';
    await session.login();
    await tester.pump(const Duration(minutes: 15));
    expect(session.view.watchStarts, 0);
    expect(session.view.logoutCalls, 0);
    expect(session.results, isEmpty);
  });
}
