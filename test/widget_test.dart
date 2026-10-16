import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/home_controller.dart';

import 'package:test_tiktok/core/desktop_user_agents.dart';
import 'package:test_tiktok/screen/home_page.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/config.dart' as config;
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_cookie_script.dart';
import 'package:test_tiktok/core/scripts/auto_interest_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/webview_locale.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';

import 'support/memory_proxy_store.dart';

class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _TestWebView(params);
}

class _TestWebView extends PlatformInAppWebViewWidget {
  _TestWebView(super.params) : super.implementation();

  @override
  Widget build(BuildContext context) => const SizedBox.expand();

  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();

  @override
  void dispose() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_identity'),
          (call) async => 'test-agent',
        );
  });
  testWidgets(
    'Browser check uses the existing WebView and stops TikTok automation',
    (tester) async {
      final logic = TikTokController(
        configuration: AppConfiguration.defaults('test-agent'),
        launchAction: TikTokLaunchAction.login,
      )..onInit();
      addTearDown(logic.onClose);
      final platform = _TestController(WebUri(tiktokHomeUrl));
      final controller = InAppWebViewController.fromPlatform(
        platform: platform,
      );
      logic.webViewController = controller;
      await logic.openBrowserCheck();
      expect(platform.loads, isEmpty);
      logic.browserIdentityReady = true;
      logic.autoWatchEnabled = true;
      await logic.openBrowserCheck();
      expect(logic.browserCheckOpen, isTrue);
      expect(logic.autoWatchEnabled, isFalse);
      expect(logic.initialPageLoaded, isFalse);
      expect(
        platform.loads.single.url.toString(),
        TikTokController.browserCheckUrl,
      );
      expect(platform.loads.single.headers, englishWebViewHeaders);
      platform.sources.clear();
      logic.onLoadStart(controller, WebUri(TikTokController.browserCheckUrl));
      await logic.onLoadStop(
        controller,
        WebUri(TikTokController.browserCheckUrl),
      );
      await logic.runInitialAction();
      await logic.startAutoWatch();
      expect(platform.sources, isEmpty);
      expect(logic.loadingProgress, 100);
      logic.goHome();
      expect(platform.loads.last.url.toString(), tiktokHomeUrl);
      logic.onLoadStart(controller, WebUri(tiktokHomeUrl));
      expect(logic.browserCheckOpen, isFalse);
    },
  );
  test('WhatIsMyIP is the settings-only IP check URL', () {
    final logic = TikTokController(
      configuration: AppConfiguration.defaults('test-agent'),
      startWithIpCheck: true,
    );

    expect(logic.initialUrl, TikTokController.ipCheckUrl);
    logic.onInit();
    addTearDown(logic.onClose);
  });
  for (final action in TikTokLaunchAction.values) {
    testWidgets(
      'Android $action waits for native Client Hints before the first URL',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        final gate = Completer<String>();
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_identity'),
          (call) {
            expect(call.method, 'configureEngine');
            expect(call.arguments['id'], 0);
            expect(call.arguments.containsKey('userAgent'), isFalse);
            return gate.future;
          },
        );
        final logic = TikTokController(
          configuration: AppConfiguration.defaults('test-agent'),
          launchAction: action,
        )..onInit();
        addTearDown(logic.onClose);
        final platform = _TestController(WebUri(tiktokHomeUrl));
        final created = logic.onWebViewCreated(
          InAppWebViewController.fromPlatform(platform: platform),
        );
        await tester.pump();
        expect(platform.loads, isEmpty);
        expect(logic.browserIdentityReady, isFalse);
        expect(logic.initialActionStarted, isFalse);
        gate.complete('test-agent');
        await created;
        expect(logic.browserIdentityReady, isTrue);
        expect(platform.loads.single.url.toString(), action.initialUrl);
        expect(platform.loads.single.headers, englishWebViewHeaders);
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      'Android $action metadata failure prevents any initial network navigation',
      (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(() => debugDefaultTargetPlatformOverride = null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_identity'),
          (call) async {
            throw PlatformException(code: 'identity_unsupported');
          },
        );
        final logic = TikTokController(
          configuration: AppConfiguration.defaults('test-agent'),
          launchAction: action,
        )..onInit();
        addTearDown(logic.onClose);
        final platform = _TestController(WebUri(tiktokHomeUrl));
        await logic.onWebViewCreated(
          InAppWebViewController.fromPlatform(platform: platform),
        );
        expect(platform.loads, isEmpty);
        expect(logic.pageFailure?.title, 'Không thể cấu hình Chrome desktop');
        expect(logic.browserIdentityReady, isFalse);
        await logic.runInitialAction();
        expect(logic.initialActionStarted, isFalse);
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
  testWidgets(
    'Home passes the selected combined configuration to a separate TikTok route and keeps it on return',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _TestWebViewPlatform();
      final proxyCalls = <MethodCall>[];
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async {
          proxyCalls.add(call);
          return null;
        },
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'),
          null,
        );
      });
      await tester.binding.setSurfaceSize(const Size(800, 2800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final proxyStore = MemoryProxyStore()
        ..current = WebViewProxy.parse('127.0.0.1:8888')
        ..currentUserAgent = desktopUserAgents.first
        ..currentAccount = const AccountCredentials(
          email: 'person@example.com',
          password: 'tiktok-password',
          mailboxPassword: 'mail-password',
        );
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: desktopUserAgents.first,
            proxyStore: proxyStore,
          ),
        ),
      );
      expect(find.byType(InAppWebView), findsNothing);
      expect(find.text('Tool TikTok'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('comments')),
        ' First comment \n\n Second comment ',
      );
      expect(find.byType(TabBar), findsOneWidget);
      expect(find.byKey(const Key('runAutoSignup')), findsNothing);
      expect(find.byKey(const Key('runAutoLogin')), findsNothing);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      final page = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(page.launchAction, TikTokLaunchAction.browse);
      expect(page.configuration.birthday, isNull);
      expect(page.configuration.signupEmail, 'person@example.com');
      expect(page.configuration.signupPassword, 'tiktok-password');
      expect(page.configuration.loginUsername, 'person@example.com');
      expect(page.configuration.loginPassword, 'tiktok-password');
      expect(page.configuration.signupOtp, isEmpty);
      expect(page.configuration.loginOtp, isEmpty);
      expect(page.configuration.comments, ['First comment', 'Second comment']);
      expect(page.configuration.userAgent, desktopUserAgents.first);
      expect(proxyCalls.single.arguments['host'], '127.0.0.1');
      expect(proxyCalls.single.arguments['port'], 8888);
      expect(find.byType(InAppWebView), findsOneWidget);
      expect(
        tester
            .widget<InAppWebView>(find.byType(InAppWebView))
            .platform
            .params
            .initialSettings!
            .userAgent,
        desktopUserAgents.first,
      );
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsNothing);
      expect(
        tester
            .widget<SelectableText>(
              find.byKey(const Key('currentProxyAccountEmail')),
            )
            .data,
        'person@example.com',
      );
      for (final action in [
        TikTokLaunchAction.login,
        TikTokLaunchAction.signup,
      ]) {
        proxyStore.currentStatus = action == TikTokLaunchAction.login
            ? AccountStatus.registered
            : AccountStatus.unregistered;
        final homeController = tester
            .state<GetBuilderState<HomeController>>(
              find.byType(GetBuilder<HomeController>),
            )
            .controller!;
        await homeController.restoreProxy();
        await tester.pumpAndSettle();
        expect(
          find.text(
            action == TikTokLaunchAction.login
                ? 'Đăng nhập tài khoản'
                : 'Đăng ký tài khoản',
          ),
          findsOneWidget,
        );
        expect(
          tester.getBottomLeft(find.byKey(const Key('runAccountAction'))).dy,
          lessThan(tester.getTopLeft(find.byKey(const Key('openTikTok'))).dy),
        );
        await tester.tap(find.byKey(const Key('runAccountAction')));
        await tester.pumpAndSettle();
        final automaticPage = tester.widget<TikTokPage>(
          find.byType(TikTokPage),
        );
        expect(automaticPage.launchAction, action);
        expect(automaticPage.configuration.proxy?.uri.host, '127.0.0.1');
        expect(automaticPage.configuration.proxy?.uri.port, 8888);
        expect(
          automaticPage.configuration.userAgent,
          page.configuration.userAgent,
        );
        expect(proxyCalls.last.arguments['host'], '127.0.0.1');
        expect(proxyCalls.last.arguments['port'], 8888);
        expect(proxyCalls.length, action == TikTokLaunchAction.login ? 2 : 3);
        expect(
          tester
              .widget<InAppWebView>(find.byType(InAppWebView))
              .platform
              .params
              .initialSettings!
              .userAgent,
          page.configuration.userAgent,
        );
        expect(find.byType(DatePickerDialog), findsNothing);
        if (action == TikTokLaunchAction.signup) {
          expect(
            automaticPage.configuration.birthday!.year,
            inInclusiveRange(1960, 2004),
          );
        }
        expect(automaticPage.configuration.signupEmail, 'person@example.com');
        expect(automaticPage.configuration.loginUsername, 'person@example.com');
        expect(automaticPage.configuration.signupOtp, isEmpty);
        expect(automaticPage.configuration.loginOtp, isEmpty);
        await tester.tap(find.byTooltip('Back'));
        await tester.pumpAndSettle();
      }
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'Home waits for proxy application, reports failure and allows retry',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _TestWebViewPlatform();
      final gate = Completer<void>();
      var attempts = 0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async {
          expect(
            call.arguments['host'],
            isNull,
          ); // Empty proxy clears old overrides.
          if (++attempts == 1) {
            await gate.future;
            throw PlatformException(
              code: 'proxy_unsupported',
              message: 'Unsupported proxy',
            );
          }
          return null;
        },
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'),
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: desktopUserAgents.first,
            proxyStore: MemoryProxyStore(),
          ),
        ),
      );
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pump();
      expect(find.byType(TikTokPage), findsNothing);
      expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('openTikTok')))
            .onPressed,
        isNull,
      );
      gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Unsupported proxy'), findsOneWidget);
      expect(find.byType(TikTokPage), findsNothing);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(find.byType(TikTokPage), findsOneWidget);
      expect(attempts, 2);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Home requires a selected account configuration for automatic actions',
    (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _TestWebViewPlatform();
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        (call) async => null,
      );
      addTearDown(() {
        debugDefaultTargetPlatformOverride = null;
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'),
          null,
        );
      });
      await tester.pumpWidget(
        MaterialApp(
          home: HomePage(
            userAgent: desktopUserAgents.first,
            proxyStore: MemoryProxyStore(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('runAccountAction')), findsNothing);
      await _launchHomeAction(tester, TikTokLaunchAction.login);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Chọn cấu hình có tài khoản trong Quản lý cấu hình trước khi chạy.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nhập email đăng ký hợp lệ.'), findsNothing);
      expect(find.byType(TikTokPage), findsNothing);
      await _launchHomeAction(tester, TikTokLaunchAction.signup);
      await tester.pumpAndSettle();
      expect(
        find.text(
          'Chọn cấu hình có tài khoản trong Quản lý cấu hình trước khi chạy.',
        ),
        findsOneWidget,
      );
      expect(find.text('Nhập tài khoản đăng nhập.'), findsNothing);
      expect(find.byType(TikTokPage), findsNothing);
      await tester.tap(find.byKey(const Key('openTikTok')));
      await tester.pumpAndSettle();
      expect(
        tester.widget<TikTokPage>(find.byType(TikTokPage)).launchAction,
        TikTokLaunchAction.browse,
      );
      debugDefaultTargetPlatformOverride = null;
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('Home general settings fit a narrow screen with enlarged text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: const TextScaler.linear(1.5)),
          child: child!,
        ),
        home: HomePage(
          userAgent: desktopUserAgents.first,
          proxyStore: MemoryProxyStore(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(TabBar), findsOneWidget);
    await tester.ensureVisible(find.byKey(const Key('comments')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home uses the shared account and default OTP API settings', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final previousPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test_tiktok/webview_proxy'),
      (call) async => null,
    );
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'),
        null,
      );
    });
    final store = MemoryProxyStore()
      ..current = WebViewProxy.parse('192.0.2.7:8080')
      ..currentAccount = const AccountCredentials(
        email: 'person@example.com',
        password: 'tiktok-secret',
        mailboxPassword: 'mail-secret',
      );
    await tester.pumpWidget(
      MaterialApp(
        home: HomePage(userAgent: desktopUserAgents.first, proxyStore: store),
      ),
    );
    await tester.pumpAndSettle();
    for (final action in [
      TikTokLaunchAction.login,
      TikTokLaunchAction.signup,
    ]) {
      expect(find.text('URL API lấy OTP'), findsNothing);
      await _launchHomeAction(tester, action);
      final configuration = tester
          .widget<TikTokPage>(find.byType(TikTokPage))
          .configuration;
      expect(configuration.otpApi!.url.toString(), config.otpApiUrl);
      expect(configuration.otpApi!.readerToken, config.otpApiToken.trim());
      expect(configuration.otpApi!.waitSeconds, 180);
      expect(configuration.signupMailboxPassword, 'mail-secret');
      expect(configuration.loginMailboxPassword, 'mail-secret');
      expect(configuration.signupEmail, 'person@example.com');
      expect(configuration.loginUsername, 'person@example.com');
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final action in TikTokLaunchAction.values) {
    testWidgets('$action opens its page and runs only the selected action once', (
      tester,
    ) async {
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _TestWebViewPlatform();
      addTearDown(() {
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
      });
      final configuration = AppConfiguration(
        userAgent: desktopUserAgents.first,
        signupEmail: 'signup@example.com',
        signupPassword: 'signup-secret',
        loginUsername: 'login-user',
        loginPassword: 'login-secret',
        comments: ['First comment'],
      );
      final page = TikTokPage(
        configuration: configuration,
        launchAction: action,
      );
      await tester.pumpWidget(MaterialApp(home: page));
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      if (debugDefaultTargetPlatformOverride != TargetPlatform.iOS) {
        expect(params.initialUrlRequest, isNull);
      } else {
        expect(params.initialUrlRequest!.url.toString(), switch (action) {
          TikTokLaunchAction.browse => tiktokHomeUrl,
          TikTokLaunchAction.login => tiktokHomeUrl,
          TikTokLaunchAction.signup => tiktokHomeUrl,
        });
        expect(params.initialUrlRequest!.url!.queryParameters['lang'], isNull);
        expect(params.initialUrlRequest!.headers, englishWebViewHeaders);
      }
      expect(
        params.initialSettings!.userAgent,
        debugDefaultTargetPlatformOverride == TargetPlatform.iOS
            ? configuration.userAgent
            : isNull,
      );
      expect(
        params.initialSettings!.preferredContentMode,
        UserPreferredContentMode.DESKTOP,
      );
      expect(
        params.initialUserScripts!.any(
          (script) => script.source == englishWebViewLocaleScript,
        ),
        forceEnglishWebViewLocale,
      );
      final controller = _TestController(WebUri(page.initialUrl));
      final cookieScript = params.initialUserScripts!.singleWhere(
        (script) => script.source == autoAcceptCookieScript,
      );
      expect(
        cookieScript.injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_END,
      );
      expect(cookieScript.forMainFrameOnly, isTrue);
      final interestScript = params.initialUserScripts!.singleWhere(
        (script) => script.source == autoSelectInterestScript,
      );
      expect(
        interestScript.injectionTime,
        UserScriptInjectionTime.AT_DOCUMENT_END,
      );
      expect(interestScript.forMainFrameOnly, isTrue);
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onWebViewCreated!.call(wrapped);
      await tester.pump();
      expect(
        controller.sources,
        isEmpty,
      ); // Never run before the first page load.
      params.onLoadStop!.call(wrapped, controller.url);
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(controller.sources, contains(autoAcceptCookieScript));
      expect(controller.sources, contains(autoSelectInterestScript));
      expect(
        controller.sources
            .where((source) => source.contains(autoLoginStepScript))
            .length,
        action == TikTokLaunchAction.login ? 1 : 0,
      );
      expect(
        controller.sources
            .where((source) => source.contains(autoSignupStepScript))
            .length,
        action == TikTokLaunchAction.signup ? 1 : 0,
      );
      // Another load, such as a reload/redirect, cannot replay account submission.
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(
        controller.sources
            .where((source) => source.contains(autoLoginStepScript))
            .length,
        action == TikTokLaunchAction.login ? 1 : 0,
      );
      expect(
        controller.sources
            .where((source) => source.contains(autoSignupStepScript))
            .length,
        action == TikTokLaunchAction.signup ? 1 : 0,
      );
      if (action == TikTokLaunchAction.login) {
        expect(
          find.byTooltip('Dừng tự động xem video và bình luận'),
          findsOneWidget,
        );
        await tester.tap(find.byKey(const Key('autoWatch')));
        await tester.pumpAndSettle();
      }
      if (action != TikTokLaunchAction.login) {
        expect(find.text('Hủy chờ'), findsNothing);
        expect(
          find.byTooltip('Đăng nhập tự động thành công để bật Auto nuôi'),
          findsOneWidget,
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('autoWatch')))
              .onPressed,
          isNull,
        );
        expect(tester.takeException(), isNull);
        return;
      }
      expect(
        find.byTooltip('Bật tự động xem video và bình luận'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('autoWatch')));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Dừng tự động xem video và bình luận'),
        findsOneWidget,
      );
      await tester.tap(find.byKey(const Key('autoWatch')));
      await tester.pumpAndSettle();
      expect(
        find.byTooltip('Bật tự động xem video và bình luận'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in [TikTokLaunchAction.signup, TikTokLaunchAction.login]) {
    testWidgets(
      '$action waits 2–10 seconds for normal steps and 200–400ms for OTP',
      (tester) async {
        final reader = _TestOtpReader();
        final controller = await _mountApiPage(tester, action, reader, [
          'waiting-form',
          'waiting-paste',
          'verification-requested',
          'waiting-otp-paste',
          'otp-submitted',
          action == TikTokLaunchAction.signup
              ? 'signup-success'
              : 'login-success',
        ]);
        final script = action == TikTokLaunchAction.signup
            ? autoSignupStepScript
            : autoLoginStepScript;
        int evaluations() =>
            controller.sources.where((s) => s.contains(script)).length;
        for (var i = 0; i < 3; i++) {
          await tester.pump(const Duration(milliseconds: 1999));
          expect(evaluations(), i);
          await _pumpAccountStep(tester);
          await tester.pump();
          expect(evaluations(), i + 1);
        }
        expect(reader.requests, hasLength(1));
        reader.response.complete('012345');
        await tester.pump();
        for (var i = 3; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 199));
          expect(evaluations(), i);
          await _pumpAccountStep(tester);
          await tester.pump();
          expect(evaluations(), i + 1);
        }
        expect(
          controller.sources.lastWhere((s) => s.contains(script)),
          contains('"otp":"012345"'),
        );
        expect(find.text('Dừng'), findsNothing);
        expect(reader.requests, hasLength(1));
      },
    );
  }

  testWidgets(
    'signup continues after OTP and remembers final password submission',
    (tester) async {
      final reader = _TestOtpReader();
      final controller =
          await _mountApiPage(tester, TikTokLaunchAction.signup, reader, [
            'verification-requested',
            'otp-submitted',
            'waiting-password-screen',
            'waiting-paste',
            'waiting-password-submit',
            'password-submitted',
            'waiting-result',
            'signup-success',
          ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      reader.response.complete('012345');
      await tester.pump();
      for (var i = 0; i < 7; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
        if (i == 1) {
          expect(
            find.text('Đang chờ màn nhập mật khẩu ổn định…'),
            findsOneWidget,
          );
        }
        if (i == 3) {
          expect(
            find.text('Đã nhập mật khẩu, chờ 10 giây trước khi bấm Sign up…'),
            findsOneWidget,
          );
        }
      }
      final sources = controller.sources
          .where((source) => source.contains(autoSignupStepScript))
          .toList();
      expect(sources, hasLength(8));
      expect(sources[2], contains('"allowOtpSubmit":false'));
      expect(sources[2], contains('"allowPasswordSubmit":true'));
      expect(sources[6], contains('"allowPasswordSubmit":false'));
      expect(sources[6], isNot(contains('"otpRequestedAt":null')));
      expect(reader.requests, hasLength(1));
      expect(find.text('Đăng ký TikTok thành công.'), findsOneWidget);
      expect(find.text('Dừng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login selects Email then requests API OTP only after TikTok feedback',
    (tester) async {
      final reader = _TestOtpReader();
      final controller =
          await _mountApiPage(tester, TikTokLaunchAction.login, reader, [
            'submitted',
            'email-verification-selected',
            'requesting-verification',
            'verification-requested',
            'waiting-otp-paste',
            'otp-submitted',
            'login-success',
          ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
        expect(reader.requests, isEmpty);
      }
      final waitingSource = controller.sources.lastWhere(
        (s) => s.contains(autoLoginStepScript),
      );
      expect(
        waitingSource,
        isNot(contains('"emailVerificationRequestedAt":null')),
      );
      expect(waitingSource, contains('"otpRequestedAt":null'));
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.requests, [('login@example.com', 'mail-secret')]);
      reader.response.complete('012345');
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
      }
      final source = controller.sources.lastWhere(
        (s) => s.contains(autoLoginStepScript),
      );
      expect(source, contains('"otp":"012345"'));
      expect(source, contains('"allowOtpSubmit":false'));
      expect(reader.requests, hasLength(1));
      expect(reader.closed, isTrue);
      expect(find.text('Đăng nhập TikTok thành công.'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login waits for the result after OTP Next before reporting success',
    (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
        tester,
        TikTokLaunchAction.login,
        reader,
        ['otp-submitted', 'waiting-result', 'login-success'],
      );
      await _pumpAccountStep(tester);
      await tester.pump();
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onLoadStart!.call(wrapped, controller.url);
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      // Next can replace the document. Keep waiting for login confirmation,
      // preserving the OTP submission guard across that navigation.
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(find.text('Dừng'), findsOneWidget);
      expect(find.text('Đăng nhập TikTok thành công.'), findsNothing);
      expect(reader.requests, isEmpty);
      await _pumpAccountStep(tester);
      await tester.pump();
      final sources = controller.sources
          .where((source) => source.contains(autoLoginStepScript))
          .toList();
      expect(sources, hasLength(3));
      expect(sources[1], contains('"allowOtpSubmit":false'));
      expect(find.text('Đăng nhập TikTok thành công.'), findsOneWidget);
      expect(find.text('Dừng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'login stops without calling API when Email selection has no feedback',
    (tester) async {
      final reader = _TestOtpReader();
      await _mountApiPage(tester, TikTokLaunchAction.login, reader, [
        'submitted',
        'email-verification-selected',
        'verification-request-failed',
      ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
      }
      expect(reader.requests, isEmpty);
      expect(
        find.textContaining('TikTok chưa xác nhận gửi mã.'),
        findsOneWidget,
      );
      expect(find.text('Dừng'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'shows backend account errors on a manual tap and preserves the rate limit',
    (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
        tester,
        TikTokLaunchAction.signup,
        reader,
        List.generate(10, (_) => 'requesting-verification'),
      );
      await _pumpAccountStep(tester);
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onConsoleMessage!(
        wrapped,
        ConsoleMessage(message: 'Login: account-api error: [7] unknown.'),
      );
      await tester.pump();
      expect(find.byKey(const Key('accountFailureBanner')), findsNothing);
      expect(find.textContaining('mã 7'), findsOneWidget);
      expect(find.text('Dừng'), findsNothing);
      expect(reader.requests, isEmpty);
      params.onConsoleMessage!(
        wrapped,
        ConsoleMessage(
          message:
              'Error: Maximum number of attempts reached. Try again later. get region err',
        ),
      );
      await tester.pump();
      expect(
        find.textContaining('TikTok đang giới hạn số lần thử'),
        findsOneWidget,
      );
      params.onConsoleMessage!(
        wrapped,
        ConsoleMessage(message: 'Login: email bind failed: 7 ().'),
      );
      await tester.pump();
      expect(
        find.textContaining('TikTok đang giới hạn số lần thử'),
        findsOneWidget,
      );
      await tester.pump(const Duration(seconds: 2));
      expect(reader.requests, isEmpty);
      expect(find.textContaining('Chưa hoàn tất đăng ký'), findsNothing);
    },
  );

  testWidgets(
    'backend account failure cancels pending OTP and ignores its late result',
    (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
        tester,
        TikTokLaunchAction.signup,
        reader,
        List.generate(10, (_) => 'otp-required'),
      );
      await _pumpAccountStep(tester);
      expect(reader.requests, hasLength(1));
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      params.onConsoleMessage!(
        InAppWebViewController.fromPlatform(platform: controller),
        ConsoleMessage(
          message:
              'Error: Maximum number of attempts reached. Try again later. get region err',
        ),
      );
      await tester.pump();
      expect(reader.closed, isTrue);
      final calls = controller.sources
          .where((s) => s.contains(autoSignupStepScript))
          .length;
      reader.response.complete('012345');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.sources.where((s) => s.contains(autoSignupStepScript)),
        hasLength(calls),
      );
      expect(find.text('Dừng'), findsNothing);
      expect(
        find.textContaining('TikTok đang giới hạn số lần thử'),
        findsOneWidget,
      );
    },
  );

  for (final action in [TikTokLaunchAction.signup, TikTokLaunchAction.login]) {
    testWidgets('inline rate limit stops $action and cancels pending OTP', (
      tester,
    ) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(tester, action, reader, [
        'otp-required',
        'account-rate-limited',
        'submitted',
      ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.requests, hasLength(1));
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.closed, isTrue);
      expect(
        find.textContaining('TikTok đang giới hạn số lần thử'),
        findsOneWidget,
      );
      expect(find.widgetWithText(SnackBarAction, 'Cấu hình'), findsOneWidget);
      expect(find.text('Dừng'), findsNothing);
      reader.response.complete('012345');
      await tester.pump(const Duration(seconds: 5));
      await tester.pump();
      final script = action == TikTokLaunchAction.signup
          ? autoSignupStepScript
          : autoLoginStepScript;
      expect(controller.sources.where((s) => s.contains(script)), hasLength(2));
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('account failure offers a return to the configuration route', (
    tester,
  ) async {
    await _mountApiPage(tester, TikTokLaunchAction.signup, _TestOtpReader(), [
      'account-rate-limited',
    ], routed: true);
    await _pumpAccountStep(tester);
    await tester.pump();
    expect(
      find.textContaining('TikTok đang giới hạn số lần thử'),
      findsOneWidget,
    );
    await tester.pump(const Duration(milliseconds: 250));
    await tester.tap(find.widgetWithText(SnackBarAction, 'Cấu hình'));
    await tester.pumpAndSettle();
    expect(find.text('Thông tin cấu hình'), findsOneWidget);
    expect(find.byType(InAppWebView), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('signup waits for Send code feedback before requesting API OTP', (
    tester,
  ) async {
    final reader = _TestOtpReader();
    final controller =
        await _mountApiPage(tester, TikTokLaunchAction.signup, reader, [
          'requesting-verification',
          'requesting-verification',
          'verification-requested',
          ...List.generate(10, (_) => 'otp-required'),
        ]);
    for (var i = 0; i < 2; i++) {
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.requests, isEmpty);
      expect(find.text('Đang chờ TikTok xác nhận gửi mã…'), findsOneWidget);
      expect(find.textContaining('Đang chờ API lấy OTP'), findsNothing);
    }
    await _pumpAccountStep(tester);
    await tester.pump();
    expect(reader.requests, [('signup@example.com', 'mail-secret')]);
    expect(find.textContaining('Đang chờ API lấy OTP'), findsOneWidget);
    expect(
      controller.sources.where(
        (source) => source.contains(autoSignupStepScript),
      ),
      hasLength(3),
    );
    await tester.tap(find.text('Dừng'));
    await tester.pump();
    await _pumpAccountStep(tester);
    expect(reader.closed, isTrue);
  });

  testWidgets(
    'signup stops with a Send code error without starting the OTP API',
    (tester) async {
      final reader = _TestOtpReader();
      await _mountApiPage(tester, TikTokLaunchAction.signup, reader, [
        'requesting-verification',
        'verification-request-failed',
      ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(find.text('Đang chờ TikTok xác nhận gửi mã…'), findsOneWidget);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.requests, isEmpty);
      expect(
        find.textContaining('TikTok chưa xác nhận gửi mã'),
        findsOneWidget,
      );
      expect(find.text('Dừng'), findsNothing);
    },
  );

  testWidgets(
    'signup continues through delayed username Skip before reporting success',
    (tester) async {
      final reader = _TestOtpReader();
      final controller =
          await _mountApiPage(tester, TikTokLaunchAction.signup, reader, [
            'otp-submitted',
            'password-submitted',
            'waiting-username-skip',
            'username-skipped',
            'signup-success',
          ]);
      await _pumpAccountStep(tester);
      await tester.pump();
      for (var i = 0; i < 2; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
      }
      expect(
        find.text('Đang chờ trước khi bỏ qua tạo tên người dùng…'),
        findsOneWidget,
      );
      expect(find.text('Dừng'), findsOneWidget);
      expect(find.text('Đăng ký TikTok thành công.'), findsNothing);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(
        find.text('Đã bấm Skip, đang chờ hoàn tất đăng ký…'),
        findsOneWidget,
      );
      expect(find.text('Dừng'), findsOneWidget);
      expect(find.text('Đăng ký TikTok thành công.'), findsNothing);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(find.text('Đăng ký TikTok thành công.'), findsOneWidget);
      expect(find.text('Dừng'), findsNothing);
      final sources = controller.sources.where(
        (source) => source.contains(autoSignupStepScript),
      );
      expect(sources, hasLength(5));
      expect(sources.last, contains('"allowPasswordSubmit":false'));
      expect(sources.last, contains('"allowOtpSubmit":false'));
      expect(reader.requests, isEmpty);
      expect(tester.takeException(), isNull);
    },
  );

  for (final action in [TikTokLaunchAction.login, TikTokLaunchAction.signup]) {
    testWidgets('$action keeps polling after requesting OTP', (tester) async {
      final previousPlatform = InAppWebViewPlatform.instance;
      InAppWebViewPlatform.instance = _TestWebViewPlatform();
      addTearDown(() {
        if (previousPlatform != null) {
          InAppWebViewPlatform.instance = previousPlatform;
        }
      });
      final page = TikTokPage(
        launchAction: action,
        configuration: AppConfiguration(
          userAgent: desktopUserAgents.first,
          signupEmail: 'signup@example.com',
          signupPassword: 'signup-secret',
          signupOtp: '012345',
          loginUsername: 'login-user',
          loginPassword: 'login-secret',
          loginOtp: '654321',
          birthday: DateTime(2000, 2, 29),
          comments: [],
        ),
      );
      await tester.pumpWidget(MaterialApp(home: page));
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      final controller = _TestController(
        WebUri(page.initialUrl),
        steps: [
          'verification-requested',
          'waiting-otp',
          'otp-submitted',
          action == TikTokLaunchAction.login
              ? 'login-success'
              : 'signup-success',
        ],
      );
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onWebViewCreated!.call(wrapped);
      await tester.pump();
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await _pumpAccountStep(tester);
        await tester.pump();
      }
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      final sources = controller.sources.where(
        (source) => source.contains(step),
      );
      expect(sources, hasLength(4));
      expect(
        sources.first,
        contains(
          '"otp":"${action == TikTokLaunchAction.login ? '654321' : '012345'}"',
        ),
      );
      expect(sources.first, contains('"otpRequestedAt":null'));
      expect(sources.elementAt(1), isNot(contains('"otpRequestedAt":null')));
      expect(sources.last, contains('"allowOtpSubmit":false'));
      expect(
        find.text(
          action == TikTokLaunchAction.login
              ? 'Đăng nhập TikTok thành công.'
              : 'Đăng ký TikTok thành công.',
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in [TikTokLaunchAction.login, TikTokLaunchAction.signup]) {
    testWidgets(
      '$action fetches OTP once after request and pastes the API code',
      (tester) async {
        final reader = _TestOtpReader();
        final clipboard = <String>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard.add(call.arguments['text'] as String);
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/comment_input'),
          (call) async => true,
        );
        addTearDown(() {
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('test_tiktok/comment_input'),
            null,
          );
        });
        final controller = await _mountApiPage(tester, action, reader, [
          'waiting-form',
          'verification-requested',
          ...List.generate(1000, (_) => 'otp-required'),
        ]);
        await _pumpAccountStep(tester);
        expect(reader.requests, isEmpty);
        await _pumpAccountStep(tester);
        expect(reader.requests, [
          (
            action == TikTokLaunchAction.login
                ? 'login@example.com'
                : 'signup@example.com',
            'mail-secret',
          ),
        ]);
        await tester.pump(const Duration(seconds: 60));
        await tester.pump(const Duration(seconds: 60));
        expect(reader.requests, hasLength(1));
        expect(find.text('Dừng'), findsOneWidget);
        reader.response.complete('012345');
        controller.steps!
          ..clear()
          ..addAll([
            'waiting-otp-paste',
            'otp-submitted',
            action == TikTokLaunchAction.login
                ? 'login-success'
                : 'signup-success',
          ]);
        await tester.pump();
        await _pumpAccountStep(tester);
        final step = action == TikTokLaunchAction.login
            ? autoLoginStepScript
            : autoSignupStepScript;
        final source = controller.sources.lastWhere(
          (source) => source.contains(step),
        );
        expect(source, contains('"otp":"012345"'));
        expect(source, isNot(contains('mail-secret')));
        expect(source, isNot(contains('test-reader-token')));
        final handler =
            controller.handlers[action == TikTokLaunchAction.login
                ? 'FlutterLoginPaste'
                : 'FlutterSignupPaste']!;
        expect(await handler([1, 'otp']), true);
        expect(clipboard, ['012345']);
        for (var i = 0; i < 2; i++) {
          await _pumpAccountStep(tester);
          await tester.pump();
        }
        expect(reader.requests, hasLength(1));
        expect(reader.closed, isTrue);
        expect(
          find.text(
            action == TikTokLaunchAction.login
                ? 'Đăng nhập TikTok thành công.'
                : 'Đăng ký TikTok thành công.',
          ),
          findsOneWidget,
        );
      },
    );

    testWidgets('$action ignores an API response after Stop', (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
        tester,
        action,
        reader,
        List.generate(10, (_) => 'otp-required'),
      );
      await _pumpAccountStep(tester);
      expect(reader.requests, hasLength(1));
      await tester.tap(find.text('Dừng'));
      await tester.pump();
      expect(reader.closed, isTrue);
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      final evaluated = controller.sources
          .where((source) => source.contains(step))
          .length;
      reader.response.complete('012345');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(
        controller.sources.where((source) => source.contains(step)),
        hasLength(evaluated),
      );
      final handler =
          controller.handlers[action == TikTokLaunchAction.login
              ? 'FlutterLoginPaste'
              : 'FlutterSignupPaste']!;
      expect(await handler([1, 'otp']), false);
    });

    testWidgets('$action reports an API error without entering an OTP', (
      tester,
    ) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(tester, action, reader, [
        'verification-requested',
        'otp-required',
      ]);
      await _pumpAccountStep(tester);
      reader.response.completeError(
        const OtpApiException('API chưa tìm thấy mã.'),
      );
      await tester.pump();
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(find.text('API chưa tìm thấy mã.'), findsOneWidget);
      expect(reader.closed, isTrue);
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      expect(
        controller.sources.where((source) => source.contains(step)),
        hasLength(1),
      );
    });

    testWidgets('$action still detects CAPTCHA while API is pending', (
      tester,
    ) async {
      final reader = _TestOtpReader();
      await _mountApiPage(tester, action, reader, [
        'verification-requested',
        'verification-required',
      ]);
      await _pumpAccountStep(tester);
      await _pumpAccountStep(tester);
      await tester.pump();
      expect(reader.closed, isTrue);
      expect(
        find.text(
          action == TikTokLaunchAction.login
              ? 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. Hãy hoàn tất trên trang đăng nhập.'
              : 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. Hãy hoàn tất trên trang đăng ký.',
        ),
        findsOneWidget,
      );
      reader.response.complete('012345');
      await tester.pump();
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final action in [
      TikTokLaunchAction.login,
      TikTokLaunchAction.signup,
    ]) {
      testWidgets('$platform $action enters credentials and OTP natively', (
        tester,
      ) async {
        debugDefaultTargetPlatformOverride = platform;
        final previousPlatform = InAppWebViewPlatform.instance;
        InAppWebViewPlatform.instance = _TestWebViewPlatform();
        final clipboard = <String>[];
        final nativePastes = <MethodCall>[];
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          (call) async {
            if (call.method == 'Clipboard.setData') {
              clipboard.add(call.arguments['text'] as String);
            }
            return null;
          },
        );
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/comment_input'),
          (call) async {
            nativePastes.add(call);
            return true;
          },
        );
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          if (previousPlatform != null) {
            InAppWebViewPlatform.instance = previousPlatform;
          }
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            SystemChannels.platform,
            null,
          );
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('test_tiktok/comment_input'),
            null,
          );
        });
        final signup = action == TikTokLaunchAction.signup;
        final page = TikTokPage(
          launchAction: action,
          configuration: AppConfiguration(
            userAgent: desktopUserAgents.first,
            signupEmail: 'signup@example.com',
            signupPassword: 'signup-secret',
            signupOtp: '012345',
            loginUsername: 'login-user',
            loginPassword: 'login-secret',
            loginOtp: '654321',
            birthday: DateTime(2000, 2, 29),
            comments: [],
          ),
        );
        await tester.pumpWidget(MaterialApp(home: page));
        final params = tester
            .widget<InAppWebView>(find.byType(InAppWebView))
            .platform
            .params;
        final controller = _TestController(
          WebUri(page.initialUrl),
          steps: List.generate(10, (_) => 'waiting-paste'),
        );
        final wrapped = InAppWebViewController.fromPlatform(
          platform: controller,
        );
        params.onWebViewCreated!.call(wrapped);
        await tester.pump();
        params.onLoadStop!.call(wrapped, controller.url);
        await tester.pump();
        await _pumpAccountStep(tester);
        await tester.pump();
        final paste = controller
            .handlers[signup ? 'FlutterSignupPaste' : 'FlutterLoginPaste']!;
        expect(await paste([99, 'email']), false);
        expect(await paste([1, 'unknown']), false);
        controller.allowAccountPaste = false;
        expect(await paste([1, 'email']), false);
        expect(clipboard, isEmpty);
        expect(nativePastes, isEmpty);
        controller.allowAccountPaste = true;
        for (final field in ['email', 'password', 'otp']) {
          expect(await paste([1, field]), true);
        }
        final expectedText = signup
            ? ['signup@example.com', 'signup-secret', '012345']
            : ['login-user', 'login-secret', '654321'];
        final keyboardInput = platform == TargetPlatform.android;
        expect(clipboard, keyboardInput ? [expectedText.last] : expectedText);
        expect(nativePastes, hasLength(3));
        for (var i = 0; i < nativePastes.length; i++) {
          final call = nativePastes[i];
          expect(call.method, keyboardInput && i < 2 ? 'typeText' : 'paste');
          expect(call.arguments, {
            'context': signup ? 'signup' : 'login',
            'attempt': 1,
            if (keyboardInput) ...{
              'field': ['email', 'password', 'otp'][i],
              'text': expectedText[i],
            },
          });
        }
        await tester.pumpWidget(const SizedBox());
        await _pumpAccountStep(tester);
        expect(await paste([1, 'otp']), false);
        expect(nativePastes, hasLength(3));
        debugDefaultTargetPlatformOverride = null;
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _launchHomeAction(
  WidgetTester tester,
  TikTokLaunchAction action,
) async {
  await tester.pumpAndSettle();
  final logic = tester
      .state<GetBuilderState<HomeController>>(
        find.byType(GetBuilder<HomeController>),
      )
      .controller!;
  final context = tester.element(find.byType(HomePage));
  unawaited(
    logic.openTikTok(action, (configuration, launchAction) {
      return Navigator.of(context).push<void>(
        MaterialPageRoute(
          builder: (_) => TikTokPage(
            configuration: configuration,
            launchAction: launchAction,
          ),
        ),
      );
    }),
  );
  await tester.pumpAndSettle();
}

// Advance only to the next account result so randomized delays cannot skip
// intermediate OTP states or let a transient notice expire before assertions.
Future<void> _pumpAccountStep(WidgetTester tester) async {
  final finder = find.byType(GetBuilder<TikTokController>);
  if (finder.evaluate().isEmpty) {
    await tester.pump(const Duration(seconds: 10));
    return;
  }
  final logic = tester
      .state<GetBuilderState<TikTokController>>(finder)
      .controller!;
  if (!logic.autoLoginBusy && !logic.autoSignupBusy) {
    await tester.pump(const Duration(seconds: 10));
    return;
  }
  final controller = logic.webViewController!.platform as _TestController;
  int evaluations() => controller.sources
      .where(
        (source) =>
            source.contains(autoLoginStepScript) ||
            source.contains(autoSignupStepScript),
      )
      .length;
  final before = evaluations();
  for (var tick = 0; tick < 500; tick++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (evaluations() > before ||
        (!logic.autoLoginBusy && !logic.autoSignupBusy)) {
      await tester.pump();
      return;
    }
  }
  fail('Account step did not complete within the maximum 10-second delay.');
}

Future<_TestController> _mountApiPage(
  WidgetTester tester,
  TikTokLaunchAction action,
  _TestOtpReader reader,
  List<String> steps, {
  bool routed = false,
}) async {
  final previousPlatform = InAppWebViewPlatform.instance;
  InAppWebViewPlatform.instance = _TestWebViewPlatform();
  addTearDown(() {
    if (previousPlatform != null) {
      InAppWebViewPlatform.instance = previousPlatform;
    }
  });
  final page = TikTokPage(
    launchAction: action,
    otpReaderFactory: (_) => reader,
    configuration: AppConfiguration(
      userAgent: desktopUserAgents.first,
      signupEmail: 'signup@example.com',
      signupPassword: 'signup-secret',
      loginUsername: 'login@example.com',
      loginPassword: 'login-secret',
      signupMailboxPassword: 'mail-secret',
      loginMailboxPassword: 'mail-secret',
      birthday: DateTime(2000, 2, 29),
      comments: [],
      otpApi: OtpApiConfiguration(
        url: Uri.parse('https://example.com/api/code'),
        readerToken: 'test-reader-token',
      ),
    ),
  );
  if (routed) {
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: const Scaffold(body: Text('Thông tin cấu hình')),
      ),
    );
    unawaited(
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page),
      ),
    );
    await tester.pumpAndSettle();
  } else {
    await tester.pumpWidget(MaterialApp(home: page));
  }
  final params = tester
      .widget<InAppWebView>(find.byType(InAppWebView))
      .platform
      .params;
  final controller = _TestController(WebUri(page.initialUrl), steps: steps);
  final wrapped = InAppWebViewController.fromPlatform(platform: controller);
  params.onWebViewCreated!.call(wrapped);
  await tester.pump();
  params.onLoadStop!.call(wrapped, controller.url);
  await tester.pump();
  return controller;
}

class _TestOtpReader implements OtpCodeReader {
  final response = Completer<String>();
  final requests = <(String, String)>[];
  bool closed = false;

  @override
  Future<String> fetchCode({required String email, required String password}) {
    requests.add((email, password));
    return response.future;
  }

  @override
  void close() => closed = true;
}

class _TestController extends PlatformInAppWebViewController {
  _TestController(this.url, {this.steps})
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  final WebUri url;
  final List<String>? steps;
  final sources = <String>[];
  final handlers = <String, JavaScriptHandlerCallback>{};
  bool allowAccountPaste = true;
  final loads = <URLRequest>[];

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    loads.add(urlRequest);
  }

  @override
  Future<WebUri?> getUrl() async => url;

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    if (source.contains('?.canPasteFromClipboard(')) return allowAccountPaste;
    if ((source.contains(autoLoginStepScript) ||
            source.contains(autoSignupStepScript)) &&
        steps != null &&
        steps!.isNotEmpty) {
      return steps!.removeAt(0);
    }
    if (source.contains(autoLoginStepScript)) return 'login-success';
    if (source.contains(autoSignupStepScript)) return 'signup-success';
    return true;
  }
}
