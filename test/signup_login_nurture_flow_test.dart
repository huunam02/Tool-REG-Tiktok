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
import 'package:test_tiktok/core/services/remote_config_service.dart';
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
  _Session(
    this.tester, {
    bool maximum = false,
    this.nurtureAfterSignup = false,
    this.logoutAfterNurture = false,
    this.autoAdvance = false,
    this.launchAction = TikTokLaunchAction.browse,
  }) : random = _BoundaryRandom(maximum);
  final WidgetTester tester;
  final bool nurtureAfterSignup;
  final bool logoutAfterNurture;
  final bool autoAdvance;
  final TikTokLaunchAction launchAction;
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
      nurtureAfterSignup: nurtureAfterSignup,
    );
    logic = TikTokController(
      configuration: configuration,
      proxyStore: store,
      useAccessibility: false,
      now: tester.binding.clock.now,
      workflowRandom: random,
      onFlowFinished: results.add,
      logoutAfterNurture: logoutAfterNurture,
      autoAdvance: autoAdvance,
      launchAction: launchAction,
    )..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: view,
    );
    logic.onNotice = (notice) => notices.add(notice.message);
    home = HomeController(
      initialUserAgent: 'agent',
      initialOtpSettings: OtpApiSettings.defaults(),
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

  Future<void> Function() fakeWebView(WidgetTester tester) {
    final previous = InAppWebViewPlatform.instance;
    final platform = _Platform();
    InAppWebViewPlatform.instance = platform;
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(
      const MethodChannel('test_tiktok/webview_proxy'),
      (_) async => null,
    );
    return () async {
      if (previous != null) InAppWebViewPlatform.instance = previous;
      debugDefaultTargetPlatformOverride = null;
      messenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        null,
      );
    };
  }

  TikTokController currentLogic(WidgetTester tester) => tester
      .state<GetBuilderState<TikTokController>>(
        find.byType(GetBuilder<TikTokController>),
      )
      .controller!;

  HomeController currentHome(WidgetTester tester) => tester
      .state<GetBuilderState<HomeController>>(
        find.byType(GetBuilder<HomeController>),
      )
      .controller!;

  /// Real-clock deadlines cannot elapse under fake timers: move them to the past.
  Future<void> finishLogout(WidgetTester tester, TikTokController logic) async {
    expect(logic.waitingToLogout, isTrue);
    logic.signupLogoutAt = DateTime.now().subtract(const Duration(seconds: 1));
    logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pumpAndSettle();
  }

  Future<void> skipAutoRunPause(WidgetTester tester) async {
    final home = currentHome(tester);
    for (var i = 0; i < 20 && home.autoRunNextAt == null; i++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
    expect(home.autoRunNextAt, isNotNull);
    home.autoRunNextAt = DateTime.now().subtract(const Duration(seconds: 1));
    await tester.pump(const Duration(milliseconds: 250));
    await tester.pumpAndSettle();
  }

  testWidgets(
    'signup continues through every unregistered configuration, nurturing when enabled',
    (tester) async {
      final restore = fakeWebView(tester);
      addTearDown(restore);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      AccountCredentials account(String name) => AccountCredentials(
        email: '$name@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final first = await store.save(
        name: 'A',
        proxy: null,
        account: account('a'),
      );
      await store.save(
        name: 'Registered',
        proxy: null,
        account: account('r'),
        statusAccount: AccountStatus.registered,
      );
      final second = await store.save(
        name: 'B',
        proxy: null,
        account: account('b'),
        nurtureAfterSignup: true,
      );
      await store.useSaved(first);
      var clears = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: 'agent',
            proxyStore: store,
            clearSession: () async => clears++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signupTab')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('signupConfiguration-$first')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signupAll')));
      await tester.pumpAndSettle();
      expect(clears, 1);
      expect(find.byKey(const Key('autoRunBanner')), findsNothing);
      var page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, first);
      expect(page.configuration.nurtureAfterSignup, isFalse);
      expect(page.autoAdvance, isTrue);
      expect(page.launchAction, TikTokLaunchAction.signup);

      final signupA = currentLogic(tester);
      final viewA = _View();
      signupA.webViewController = InAppWebViewController.fromPlatform(
        platform: viewA,
      );
      final registrationA = signupA.autoSignup();
      await tester.pump();
      for (var i = 0; i < 11 && signupA.autoSignupBusy; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await registrationA;
      await tester.pump();
      expect(find.textContaining('Tự đăng xuất sau'), findsOneWidget);
      expect(signupA.autoWatchEnabled, isFalse);
      await finishLogout(tester, signupA);
      expect(viewA.logoutCalls, 3);
      expect(find.byType(TikTokPage), findsNothing);
      expect(find.byKey(const Key('autoRunBanner')), findsOneWidget);

      await skipAutoRunPause(tester);
      expect(clears, 2);
      page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, second);
      expect(page.configuration.nurtureAfterSignup, isTrue);
      final signupB = currentLogic(tester);
      final viewB = _View();
      signupB.webViewController = InAppWebViewController.fromPlatform(
        platform: viewB,
      );
      final registrationB = signupB.autoSignup();
      await tester.pump();
      for (var i = 0; i < 11 && signupB.autoSignupBusy; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await registrationB;
      await tester.pump();
      expect(signupB.autoWatchEnabled, isTrue);
      expect(signupB.waitingToLogout, isFalse);
      expect(viewB.watchStarts, 1);
      await tester.pump(const Duration(minutes: 3));
      await tester.pump();
      expect(signupB.autoWatchEnabled, isFalse);
      expect(
        find.textContaining('Đã nuôi xong. Tự đăng xuất sau'),
        findsOneWidget,
      );
      await finishLogout(tester, signupB);
      expect(viewB.logoutCalls, 3);
      expect(find.byType(TikTokPage), findsNothing);
      expect(find.byKey(const Key('autoRunBanner')), findsNothing);
      expect(
        find.text('Đã tự đăng ký 2 cấu hình: 2 xong, 0 lỗi.'),
        findsOneWidget,
      );
      expect(
        store.entries.map((entry) => entry.statusAccount),
        everyElement(AccountStatus.registered),
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await restore();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Nuôi toàn bộ logs in to each registered account and logs out after nurture',
    (tester) async {
      final restore = fakeWebView(tester);
      addTearDown(restore);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      AccountCredentials account(String name) => AccountCredentials(
        email: '$name@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final first = await store.save(
        name: 'A',
        proxy: null,
        account: account('a'),
        statusAccount: AccountStatus.registered,
      );
      await store.save(name: 'New', proxy: null, account: account('n'));
      final second = await store.save(
        name: 'B',
        proxy: null,
        account: account('b'),
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(second);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: 'agent',
            proxyStore: store,
            clearSession: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      expect(find.text('Tài khoản đã đăng ký số lượng: 2'), findsOneWidget);
      expect(find.text('Chạy nuôi lần lượt các tài khoản'), findsOneWidget);
      // Tapping an account nurtures it first.
      await tester.tap(find.byKey(const Key('nurtureAccount-b@example.com')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('nurtureAll')));
      await tester.pumpAndSettle();
      var page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      // The selected account goes first, then the others in list order.
      expect(page.configuration.configurationId, second);
      expect(page.launchAction, TikTokLaunchAction.login);
      expect(page.logoutAfterNurture, isTrue);
      final loginB = currentLogic(tester);
      final viewB = _View();
      loginB.webViewController = InAppWebViewController.fromPlatform(
        platform: viewB,
      );
      final authentication = loginB.autoLogin();
      await tester.pump();
      for (var i = 0; i < 11 && loginB.autoLoginBusy; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      await authentication;
      expect(loginB.autoWatchEnabled, isTrue);
      await tester.pump(const Duration(minutes: 3));
      await tester.pump();
      await finishLogout(tester, loginB);
      expect(viewB.logoutCalls, 3);
      expect(find.byType(TikTokPage), findsNothing);
      await skipAutoRunPause(tester);
      page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, first);
      // Closing the screen stops the run.
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      expect(find.byKey(const Key('autoRunBanner')), findsNothing);
      expect(
        find.text('Đã dừng tự nuôi sau 1 cấu hình (1 xong, 0 lỗi).'),
        findsOneWidget,
      );
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await restore();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Đăng ký lists pending configurations and runs the tapped one first',
    (tester) async {
      final restore = fakeWebView(tester);
      addTearDown(restore);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      AccountCredentials account(String name) => AccountCredentials(
        email: '$name@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final a = await store.save(name: 'A', proxy: null, account: account('a'));
      final registered = await store.save(
        name: 'Registered',
        proxy: null,
        account: account('r'),
        statusAccount: AccountStatus.registered,
      );
      final failed = await store.save(
        name: 'Failed',
        proxy: null,
        account: account('f'),
      );
      await store.recordSignupFailure(failed, 'f@example.com', message: 'x');
      final noAccount = await store.save(name: 'Empty', proxy: null);
      final b = await store.save(name: 'B', proxy: null, account: account('b'));
      final c = await store.save(name: 'C', proxy: null, account: account('c'));
      await store.useSaved(b);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: 'agent',
            proxyStore: store,
            clearSession: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('signupTab')));
      await tester.pumpAndSettle();
      expect(find.text('Chờ đăng ký: 3'), findsOneWidget);
      for (final id in [registered, failed, noAccount]) {
        expect(find.byKey(Key('signupConfiguration-$id')), findsNothing);
      }
      // Newest first; the top one runs first until another is tapped.
      final top = tester.getTopLeft(find.byKey(Key('signupConfiguration-$c')));
      expect(
        tester.getTopLeft(find.byKey(Key('signupConfiguration-$a'))).dy,
        greaterThan(top.dy),
      );
      expect(currentHome(tester).signupPriority?.id, c);
      await tester.tap(find.byKey(Key('signupConfiguration-$a')));
      await tester.pumpAndSettle();
      expect(currentHome(tester).signupPriority?.id, a);
      expect(
        find.descendant(
          of: find.byKey(Key('signupConfiguration-$a')),
          matching: find.text('Chạy trước'),
        ),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('signupAll')));
      await tester.pumpAndSettle();
      var page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, a);
      expect(page.launchAction, TikTokLaunchAction.signup);
      // A finished account hands over to the next one in the list.
      tester
          .state<NavigatorState>(find.byType(Navigator))
          .pop(TikTokFlowResult.signupLoggedOut);
      await tester.pumpAndSettle();
      await skipAutoRunPause(tester);
      page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, c);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await restore();
      expect(tester.takeException(), isNull);
    },
  );

  for (final failed in [false, true]) {
    testWidgets(
      '${failed ? 'Cấu hình lỗi' : 'Nuôi'} runs the tapped item first, '
      'then the list in its shown order',
      (tester) async {
        final restore = fakeWebView(tester);
        addTearDown(restore);
        await tester.binding.setSurfaceSize(const Size(900, 1400));
        addTearDown(() => tester.binding.setSurfaceSize(null));
        final store = MemoryProxyStore();
        final ids = <int>[];
        for (final name in ['a', 'b', 'c']) {
          final id = await store.save(
            name: name,
            proxy: null,
            account: AccountCredentials(
              email: '$name@example.com',
              password: 'password',
              mailboxPassword: 'mail',
            ),
            statusAccount: failed
                ? AccountStatus.unregistered
                : AccountStatus.registered,
          );
          if (failed) {
            await store.recordSignupFailure(
              id,
              '$name@example.com',
              message: 'x',
            );
          }
          ids.add(id);
        }
        await tester.pumpWidget(
          MaterialApp(
            home: HomePage(
              userAgent: 'agent',
              proxyStore: store,
              clearSession: () async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(Key(failed ? 'failedTab' : 'nurtureTab')));
        await tester.pumpAndSettle();
        final home = currentHome(tester);
        Finder card(int id) => find.byKey(
          Key(
            failed
                ? 'failedConfiguration-$id'
                : 'nurtureAccount-${'abc'[ids.indexOf(id)]}@example.com',
          ),
        );
        // The list as shown, top to bottom.
        final shown = [...ids]
          ..sort(
            (x, y) => tester
                .getTopLeft(card(x))
                .dy
                .compareTo(tester.getTopLeft(card(y)).dy),
          );
        int? priority() => failed
            ? home.failedPriority?.configuration.id
            : home.nurturePriority?.configurationId;
        expect(priority(), shown.first);
        await tester.ensureVisible(card(shown[1]));
        await tester.tap(card(shown[1]));
        await tester.pumpAndSettle();
        expect(priority(), shown[1]);
        await tester.tap(
          find.byKey(Key(failed ? 'retryFailedSignups' : 'nurtureAll')),
        );
        await tester.pumpAndSettle();
        final opened = <int?>[];
        for (var i = 0; i < 3; i++) {
          if (i > 0) await skipAutoRunPause(tester);
          opened.add(
            tester
                .widget<TikTokPage>(find.byType(TikTokPage))
                .configuration
                .configurationId,
          );
          tester
              .state<NavigatorState>(find.byType(Navigator))
              .pop(TikTokFlowResult.failed);
          await tester.pumpAndSettle();
        }
        expect(opened, [shown[1], shown[0], shown[2]]);
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpAndSettle();
        await restore();
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'Cấu hình only manages configurations and lists keywords and comments',
    (tester) async {
      final restore = fakeWebView(tester);
      addTearDown(restore);
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
        statusAccount: AccountStatus.registered,
      );
      await store.useSaved(id);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(userAgent: 'agent', proxyStore: store),
        ),
      );
      await tester.pumpAndSettle();
      // No configuration in use is shown and nothing runs from here.
      expect(find.byKey(const Key('manageProxies')), findsOneWidget);
      for (final key in ['runAccountAction', 'openTikTok']) {
        expect(find.byKey(Key(key)), findsNothing);
      }
      expect(find.text('person@example.com'), findsNothing);
      expect(find.byKey(const Key('searchKeywordList')), findsOneWidget);
      expect(find.byKey(const Key('commentList')), findsOneWidget);
      expect(
        find.text(RemoteConfig.searchKeywords.first, findRichText: true),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('nurtureTab')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('nurtureAll')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await restore();
      expect(tester.takeException(), isNull);
    },
  );

  for (final maximum in [false, true]) {
    testWidgets(
      'signup waits ${maximum ? 2 : 1} minutes and confirms logout before returning',
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
            Duration(minutes: maximum ? 2 : 1) - const Duration(seconds: 1),
          ),
        );
        expect(wait, lessThanOrEqualTo(Duration(minutes: maximum ? 2 : 1)));
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

  testWidgets(
    'signup with nurture warms up 2–3 minutes, holds, then logs out',
    (tester) async {
      final session = _Session(tester, nurtureAfterSignup: true);
      await session.init();
      await session.signup();
      await tester.pump();
      expect(session.store.currentStatus, AccountStatus.registered);
      expect(session.logic.loginConfirmed, isTrue);
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.logic.waitingToLogout, isFalse);
      expect(session.view.watchStarts, 1);
      // _BoundaryRandom(false) draws the shortest, 2-minute session.
      await tester.pump(const Duration(minutes: 2));
      await tester.pump();
      expect(session.logic.autoWatchEnabled, isFalse);
      expect(session.logic.waitingToLogout, isTrue);
      expect(session.logic.logoutFollowsNurture, isTrue);
      expect(
        session.logic.signupLogoutAt!.difference(tester.binding.clock.now()),
        lessThanOrEqualTo(const Duration(minutes: 1)),
      );
      expect(session.results, isEmpty);
      await session.reachLogout();
      await tester.pump(const Duration(milliseconds: 700));
      await tester.pump(const Duration(milliseconds: 700));
      expect(session.results, [TikTokFlowResult.nurtureLoggedOut]);
      expect(session.view.logoutCalls, 3);
    },
  );

  testWidgets('automatic nurture holds 1–2 minutes then logs out', (
    tester,
  ) async {
    final session = _Session(tester, maximum: true, logoutAfterNurture: true);
    await session.init();
    await session.login();
    expect(session.logic.autoWatchEnabled, isTrue);
    await tester.pump(const Duration(minutes: 3));
    await tester.pump();
    expect(session.results, isEmpty);
    expect(session.logic.waitingToLogout, isTrue);
    final wait = session.logic.signupLogoutAt!.difference(
      tester.binding.clock.now(),
    );
    expect(wait, lessThanOrEqualTo(const Duration(minutes: 2)));
    expect(wait, greaterThanOrEqualTo(const Duration(minutes: 2, seconds: -2)));
    await session.reachLogout();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(session.results, [TikTokFlowResult.nurtureLoggedOut]);
  });

  testWidgets('automatic nurture failure still logs the account out', (
    tester,
  ) async {
    final session = _Session(tester, logoutAfterNurture: true);
    await session.init();
    await session.login();
    session.logic.handleAutoWatchMessage('comments-unavailable');
    await tester.pump();
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.logic.waitingToLogout, isTrue);
    await session.reachLogout();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(session.results, [TikTokFlowResult.nurtureLoggedOut]);
  });

  for (final stopped in [false, true]) {
    testWidgets(
      'automatic run ${stopped ? 'stays after Dừng' : 'moves on 15 seconds after'} a failed signup',
      (tester) async {
        final session = _Session(
          tester,
          autoAdvance: true,
          launchAction: TikTokLaunchAction.signup,
        );
        debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
        await session.init();
        session.view.signupResult = 'signup-error';
        session.logic.initialPageLoaded = true;
        final run = session.logic.runInitialAction();
        await tester.pump();
        for (var i = 0; i < 11 && session.logic.autoSignupBusy; i++) {
          await tester.pump(const Duration(seconds: 1));
        }
        await run;
        expect(session.logic.autoRunFailing, isTrue);
        await tester.pump();
        final logged = session.store.signupFailures.single;
        expect(logged.configurationId, session.configuration.configurationId);
        expect(logged.email, 'person@example.com');
        expect(logged.message, contains('TikTok báo lỗi đăng ký'));
        expect(
          (await session.store.listFailedConfigurations()).single.failureCount,
          1,
        );
        if (stopped) session.logic.stopByUser();
        await tester.pump(const Duration(seconds: 14));
        expect(session.results, isEmpty);
        await tester.pump(const Duration(seconds: 1));
        expect(session.results, stopped ? isEmpty : [TikTokFlowResult.failed]);
        await tester.pump(const Duration(minutes: 20));
        expect(session.results, stopped ? isEmpty : hasLength(1));
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  testWidgets('a stuck automatic signup logs the timeout as its reason', (
    tester,
  ) async {
    final session = _Session(
      tester,
      autoAdvance: true,
      launchAction: TikTokLaunchAction.signup,
    );
    await session.init();
    await tester.pump(TikTokController.autoFlowTimeout);
    await tester.pump();
    expect(
      session.store.signupFailures.single.message,
      'Quá 15 phút chưa xong cấu hình này.',
    );
    await tester.pump(TikTokController.autoFailureDelay);
    expect(session.results, [TikTokFlowResult.failed]);
  });

  testWidgets('a successful automatic signup leaves no failure log', (
    tester,
  ) async {
    final session = _Session(
      tester,
      autoAdvance: true,
      launchAction: TikTokLaunchAction.signup,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await session.init();
    await session.store.recordSignupFailure(
      session.configuration.configurationId!,
      session.configuration.signupEmail,
      message: 'earlier failure',
    );
    session.logic.initialPageLoaded = true;
    final run = session.logic.runInitialAction();
    await tester.pump();
    for (var i = 0; i < 11 && session.logic.autoSignupBusy; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await run;
    expect(session.store.signupFailures, hasLength(1));
    expect(await session.store.listFailedConfigurations(), isEmpty);
    await session.reachLogout();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(session.results, [TikTokFlowResult.signupLoggedOut]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'Cấu hình lỗi lists failed signups and Đăng ký lại runs only them',
    (tester) async {
      final restore = fakeWebView(tester);
      addTearDown(restore);
      await tester.binding.setSurfaceSize(const Size(900, 1400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final store = MemoryProxyStore();
      AccountCredentials account(String name) => AccountCredentials(
        email: '$name@example.com',
        password: 'password',
        mailboxPassword: 'mail',
      );
      final failed = await store.save(
        name: 'Failed',
        proxy: null,
        account: account('failed'),
      );
      final fresh = await store.save(
        name: 'Fresh',
        proxy: null,
        account: account('fresh'),
      );
      await store.recordSignupFailure(
        failed,
        'failed@example.com',
        message: 'TikTok báo lỗi tài khoản (mã 1023).',
        step: 'Đang mở danh sách Year…',
        at: DateTime(2026, 10, 18, 1, 34),
      );
      await store.recordSignupFailure(
        failed,
        'failed@example.com',
        message: 'TikTok đang giới hạn số lần thử',
        at: DateTime(2026, 10, 18, 2, 16),
      );
      await store.useSaved(failed);
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: 'agent',
            proxyStore: store,
            clearSession: () async {},
          ),
        ),
      );
      await tester.pumpAndSettle();

      // The normal signup run leaves failed configurations to this tab.
      await tester.tap(find.byKey(const Key('signupTab')));
      await tester.pumpAndSettle();
      expect(find.byKey(Key('signupConfiguration-$failed')), findsNothing);
      await tester.tap(find.byKey(const Key('signupAll')));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<TikTokPage>(find.byType(TikTokPage))
            .configuration
            .configurationId,
        fresh,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const Key('failedTab')));
      await tester.pumpAndSettle();
      expect(find.text('Cấu hình lỗi: 1'), findsOneWidget);
      expect(find.byKey(Key('failedConfiguration-$failed')), findsOneWidget);
      expect(find.text('Lỗi 2 lần'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(Key('latestFailure-$failed')),
          matching: find.text('TikTok đang giới hạn số lần thử'),
        ),
        findsOneWidget,
      );
      expect(find.text('TikTok báo lỗi tài khoản (mã 1023).'), findsNothing);
      await tester.tap(find.byKey(Key('failureLog-$failed')));
      await tester.pumpAndSettle();
      expect(find.text('TikTok báo lỗi tài khoản (mã 1023).'), findsOneWidget);
      expect(find.text('Bước: Đang mở danh sách Year…'), findsOneWidget);

      await tester.tap(find.byKey(const Key('retryFailedSignups')));
      await tester.pumpAndSettle();
      final page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.configuration.configurationId, failed);
      expect(page.launchAction, TikTokLaunchAction.signup);
      expect(page.autoAdvance, isTrue);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(
        find.text('Đã dừng tự đăng ký lại sau 0 cấu hình (0 xong, 0 lỗi).'),
        findsOneWidget,
      );

      await tester.ensureVisible(find.byKey(Key('dismissFailure-$failed')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(Key('dismissFailure-$failed')));
      await tester.pumpAndSettle();
      expect(find.text('Không có cấu hình lỗi'), findsOneWidget);
      expect(store.signupFailures, hasLength(2));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pumpAndSettle();
      await restore();
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('automatic run gives up on a stuck configuration', (
    tester,
  ) async {
    final session = _Session(tester, autoAdvance: true);
    await session.init();
    await tester.pump(TikTokController.autoFlowTimeout);
    expect(session.results, isEmpty);
    await tester.pump(TikTokController.autoFailureDelay);
    expect(session.results, [TikTokFlowResult.failed]);
  });

  testWidgets('a successful automatic signup does not report failure', (
    tester,
  ) async {
    final session = _Session(
      tester,
      autoAdvance: true,
      launchAction: TikTokLaunchAction.signup,
    );
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    await session.init();
    session.logic.initialPageLoaded = true;
    final run = session.logic.runInitialAction();
    await tester.pump();
    for (var i = 0; i < 11 && session.logic.autoSignupBusy; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
    await run;
    expect(session.logic.autoRunFailing, isFalse);
    await session.reachLogout();
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 700));
    expect(session.results, [TikTokFlowResult.signupLoggedOut]);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
    'automatic login nurtures for two minutes then returns without logout',
    (tester) async {
      final session = _Session(tester);
      await session.init();
      await session.login();
      expect(session.logic.autoWatchEnabled, isTrue);
      expect(session.results, isEmpty);
      // _BoundaryRandom(false) draws the shortest, 2-minute session.
      await tester.pump(const Duration(minutes: 1, seconds: 58));
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
