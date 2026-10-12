import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:test_tiktok/desktop_user_agents.dart';
import 'package:test_tiktok/home_page.dart';
import 'package:test_tiktok/tiktok_page.dart';
import 'package:test_tiktok/app_configuration.dart';
import 'package:test_tiktok/config.dart' as config;
import 'package:test_tiktok/auto_login_script.dart';
import 'package:test_tiktok/auto_cookie_script.dart';
import 'package:test_tiktok/auto_signup_script.dart';
import 'package:test_tiktok/otp_api.dart';

class _TestWebViewPlatform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) =>
      _TestWebView(params);
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
  testWidgets(
      'Home passes edited configuration to a separate TikTok route and keeps it on return',
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
          const MethodChannel('test_tiktok/webview_proxy'), null);
    });
    await tester.binding.setSurfaceSize(const Size(800, 2800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      home: HomePage(userAgent: desktopUserAgents.first),
    ));
    expect(find.byType(InAppWebView), findsNothing);
    expect(find.text('Cấu hình TikTok'), findsOneWidget);
    expect(find.text(desktopUserAgents.first), findsOneWidget);
    await tester.enterText(find.byKey(const Key('proxyUrl')), '127.0.0.1:8888');
    await tester.enterText(find.byKey(const Key('comments')),
        ' First comment \n\n Second comment ');
    await _selectHomeTab(tester, 'signupTab');
    await tester.enterText(
        find.byKey(const Key('signupEmail')), 'signup@example.com');
    await tester.enterText(
        find.byKey(const Key('signupPassword')), 'signup-password');
    await tester.enterText(
        find.byKey(const Key('signupMailboxPassword')), 'signup-mail-secret');
    expect(
        find.byKey(const Key('signupOtp'), skipOffstage: false), findsNothing);
    expect(find.byKey(const Key('signupBirthday')), findsNothing);
    expect(find.text('Chạy đăng ký tự động'), findsOneWidget);
    expect(find.byKey(const Key('runAutoLogin')), findsNothing);
    await _selectHomeTab(tester, 'loginTab');
    await tester.enterText(
        find.byKey(const Key('loginUsername')), 'login@example.com');
    await tester.enterText(
        find.byKey(const Key('loginPassword')), 'login-password');
    await tester.enterText(
        find.byKey(const Key('loginMailboxPassword')), 'login-mail-secret');
    expect(
        find.byKey(const Key('loginOtp'), skipOffstage: false), findsNothing);
    expect(find.text('Chạy đăng nhập tự động'), findsOneWidget);
    expect(find.byKey(const Key('runAutoSignup')), findsNothing);
    await _selectHomeTab(tester, 'generalTab');
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    final page = tester.widget<TikTokPage>(find.byType(TikTokPage));
    expect(page.launchAction, TikTokLaunchAction.browse);
    expect(page.configuration.birthday, isNull);
    expect(page.configuration.signupEmail, 'signup@example.com');
    expect(page.configuration.signupPassword, 'signup-password');
    expect(page.configuration.loginUsername, 'login@example.com');
    expect(page.configuration.loginPassword, 'login-password');
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
        desktopUserAgents.first);
    await tester.tap(find.byTooltip('Back'));
    await tester.pumpAndSettle();
    expect(find.byType(TikTokPage), findsNothing);
    await _selectHomeTab(tester, 'signupTab');
    expect(
        tester
            .widget<TextFormField>(find.byKey(const Key('signupEmail')))
            .controller!
            .text,
        'signup@example.com');
    for (final entry in {
      'runAutoLogin': TikTokLaunchAction.login,
      'runAutoSignup': TikTokLaunchAction.signup,
    }.entries) {
      await _selectHomeTab(tester,
          entry.value == TikTokLaunchAction.login ? 'loginTab' : 'signupTab');
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pumpAndSettle();
      final automaticPage = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(automaticPage.launchAction, entry.value);
      expect(find.byType(DatePickerDialog), findsNothing);
      if (entry.value == TikTokLaunchAction.signup) {
        expect(automaticPage.configuration.birthday!.year,
            inInclusiveRange(1960, 2004));
      }
      expect(automaticPage.configuration.signupEmail, 'signup@example.com');
      expect(automaticPage.configuration.loginUsername, 'login@example.com');
      expect(automaticPage.configuration.signupOtp, isEmpty);
      expect(automaticPage.configuration.loginOtp, isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });

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
        expect(call.arguments['host'],
            isNull); // Empty proxy clears old overrides.
        if (++attempts == 1) {
          await gate.future;
          throw PlatformException(
              code: 'proxy_unsupported', message: 'Unsupported proxy');
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
          const MethodChannel('test_tiktok/webview_proxy'), null);
    });
    await tester.pumpWidget(
        MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pump();
    expect(find.byType(TikTokPage), findsNothing);
    expect(
        tester
            .widget<OutlinedButton>(find.byKey(const Key('openTikTok')))
            .onPressed,
        isNull);
    gate.complete();
    await tester.pumpAndSettle();
    expect(find.text('Unsupported proxy'), findsOneWidget);
    expect(find.byType(TikTokPage), findsNothing);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(find.byType(TikTokPage), findsOneWidget);
    expect(attempts, 2);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'Home validates only the selected account action, including offscreen fields',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final previousPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/webview_proxy'), (call) async => null);
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'), null);
    });
    await tester.pumpWidget(
        MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
    // Controller updates model fields below the viewport; validation must still see them.
    for (final key in [
      'signupEmail',
      'signupPassword',
      'loginUsername',
      'loginPassword'
    ]) {
      tester
          .widget<TextFormField>(find.byKey(Key(key), skipOffstage: false))
          .controller!
          .clear();
    }
    await _selectHomeTab(tester, 'loginTab');
    await tester.tap(find.byKey(const Key('runAutoLogin')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tài khoản đăng nhập.'), findsOneWidget);
    expect(find.text('Nhập email đăng ký hợp lệ.'), findsNothing);
    expect(find.byType(TikTokPage), findsNothing);
    await _selectHomeTab(tester, 'signupTab');
    await tester.tap(find.byKey(const Key('runAutoSignup')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email đăng ký hợp lệ.'), findsOneWidget);
    expect(find.text('Nhập tài khoản đăng nhập.'), findsNothing);
    expect(find.byType(TikTokPage), findsNothing);
    await _selectHomeTab(tester, 'generalTab');
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(tester.widget<TikTokPage>(find.byType(TikTokPage)).launchAction,
        TikTokLaunchAction.browse);
    debugDefaultTargetPlatformOverride = null;
    expect(tester.takeException(), isNull);
  });

  testWidgets('Home rejects an invalid proxy without opening a WebView',
      (tester) async {
    await tester.pumpWidget(
        MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
    await tester.enterText(
        find.byKey(const Key('proxyUrl')), 'http://localhost:99999');
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập proxy HTTP/HTTPS dạng host:port.'), findsOneWidget);
    expect(find.byType(TikTokPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  for (final tab in ['signupTab', 'loginTab']) {
    testWidgets('Home shows invalid shared settings when opening from $tab',
        (tester) async {
      await tester.pumpWidget(
          MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
      await tester.enterText(
          find.byKey(const Key('proxyUrl')), 'http://localhost:99999');
      await _selectHomeTab(tester, tab);
      await tester.tap(find
          .byKey(Key(tab == 'signupTab' ? 'runAutoSignup' : 'runAutoLogin')));
      await tester.pumpAndSettle();
      expect(
          find.text('Nhập proxy HTTP/HTTPS dạng host:port.'), findsOneWidget);
      expect(find.byKey(const Key('openTikTok')), findsOneWidget);
      expect(find.byType(TikTokPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Home tabs fit a narrow screen with enlarged text',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: const TextScaler.linear(1.5)),
        child: child!,
      ),
      home: HomePage(userAgent: desktopUserAgents.first),
    ));
    for (final tab in ['signupTab', 'loginTab', 'generalTab']) {
      await _selectHomeTab(tester, tab);
      expect(tester.takeException(), isNull);
    }
  });

  testWidgets(
      'Home uses file API settings and keeps separate mailbox passwords',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    final previousPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _TestWebViewPlatform();
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('test_tiktok/webview_proxy'),
      (call) async => null,
    );
    await tester.binding.setSurfaceSize(const Size(800, 2800));
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          const MethodChannel('test_tiktok/webview_proxy'), null);
      return tester.binding.setSurfaceSize(null);
    });
    await tester.pumpWidget(
        MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
    expect(find.text('API lấy OTP'), findsNothing);
    for (final prefix in ['signup', 'login']) {
      await _selectHomeTab(tester, '${prefix}Tab');
      expect(find.text('API lấy OTP'), findsOneWidget);
      expect(find.byType(SwitchListTile), findsNothing);
      expect(find.byKey(Key('${prefix}OtpApiUrl')), findsNothing);
      expect(find.byKey(Key('${prefix}OtpApiToken')), findsNothing);
      expect(find.text('URL API lấy OTP'), findsNothing);
      expect(find.text('Token API lấy OTP'), findsNothing);
      expect(find.byKey(Key('${prefix}MailboxPassword')), findsOneWidget);
      await tester.enterText(
          find.byKey(Key(prefix == 'signup' ? 'signupEmail' : 'loginUsername')),
          '$prefix@example.com');
      await tester.enterText(
          find.byKey(Key('${prefix}Password')), '$prefix-tiktok-secret');
      await tester.enterText(
          find.byKey(Key('${prefix}MailboxPassword')), '$prefix-mail-secret');
    }
    for (final prefix in ['login', 'signup']) {
      await _selectHomeTab(tester, '${prefix}Tab');
      expect(
          tester
              .widget<TextFormField>(
                  find.byKey(Key('${prefix}MailboxPassword')))
              .controller!
              .text,
          '$prefix-mail-secret');
      await tester.tap(find
          .byKey(Key(prefix == 'signup' ? 'runAutoSignup' : 'runAutoLogin')));
      await tester.pumpAndSettle();
      final configuration =
          tester.widget<TikTokPage>(find.byType(TikTokPage)).configuration;
      expect(configuration.otpApi!.url.toString(), config.otpApiUrl);
      expect(configuration.otpApi!.readerToken == config.otpApiToken.trim(),
          isTrue);
      expect(configuration.otpApi!.waitSeconds, 180);
      expect(configuration.signupMailboxPassword, 'signup-mail-secret');
      expect(configuration.loginMailboxPassword, 'login-mail-secret');
      expect(configuration.signupOtp, isEmpty);
      expect(configuration.loginOtp, isEmpty);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
    }
    await _selectHomeTab(tester, 'generalTab');
    expect(find.text('API lấy OTP'), findsNothing);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    expect(
        tester.widget<TikTokPage>(find.byType(TikTokPage)).configuration.otpApi,
        isNull);
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  for (final prefix in ['signup', 'login']) {
    testWidgets('Home requires the mailbox password for $prefix',
        (tester) async {
      await tester.binding.setSurfaceSize(const Size(800, 1800));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
          MaterialApp(home: HomePage(userAgent: desktopUserAgents.first)));
      await _selectHomeTab(tester, '${prefix}Tab');
      await tester.enterText(
          find.byKey(Key(prefix == 'signup' ? 'signupEmail' : 'loginUsername')),
          '$prefix@example.com');
      await tester.enterText(
          find.byKey(Key('${prefix}Password')), 'tiktok-secret');
      await tester.tap(find
          .byKey(Key(prefix == 'signup' ? 'runAutoSignup' : 'runAutoLogin')));
      await tester.pumpAndSettle();
      expect(
          find.text(
              'Nhập mật khẩu hộp thư của email ${prefix == 'signup' ? 'đăng ký' : 'đăng nhập'}.'),
          findsOneWidget);
      expect(find.byType(TikTokPage), findsNothing);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in TikTokLaunchAction.values) {
    testWidgets('$action opens its page and runs only the selected action once',
        (tester) async {
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
      final page =
          TikTokPage(configuration: configuration, launchAction: action);
      await tester.pumpWidget(MaterialApp(home: page));
      final params = tester
          .widget<InAppWebView>(find.byType(InAppWebView))
          .platform
          .params;
      expect(
          params.initialUrlRequest!.url.toString(),
          switch (action) {
            TikTokLaunchAction.browse => tiktokHomeUrl,
            TikTokLaunchAction.login => tiktokLoginUrl,
            TikTokLaunchAction.signup => tiktokSignupUrl,
          });
      final controller = _TestController(WebUri(page.initialUrl));
      final cookieScript = params.initialUserScripts!
          .singleWhere((script) => script.source == autoAcceptCookieScript);
      expect(cookieScript.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_END);
      expect(cookieScript.forMainFrameOnly, isTrue);
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onWebViewCreated!.call(wrapped);
      expect(
          controller.sources, isEmpty); // Never run before the first page load.
      params.onLoadStop!.call(wrapped, controller.url);
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsNothing);
      expect(controller.sources, contains(autoAcceptCookieScript));
      expect(
          controller.sources
              .where((source) => source.contains(autoLoginStepScript))
              .length,
          action == TikTokLaunchAction.login ? 1 : 0);
      expect(
          controller.sources
              .where((source) => source.contains(autoSignupStepScript))
              .length,
          action == TikTokLaunchAction.signup ? 1 : 0);
      // Another load, such as a reload/redirect, cannot replay account submission.
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(
          controller.sources
              .where((source) => source.contains(autoLoginStepScript))
              .length,
          action == TikTokLaunchAction.login ? 1 : 0);
      expect(
          controller.sources
              .where((source) => source.contains(autoSignupStepScript))
              .length,
          action == TikTokLaunchAction.signup ? 1 : 0);
      expect(find.text('Bật auto xem và bình luận'), findsOneWidget);
      await tester.tap(find.byKey(const Key('autoWatch')));
      await tester.pumpAndSettle();
      expect(find.text('Dừng tự động'), findsOneWidget);
      await tester.tap(find.byKey(const Key('autoWatch')));
      await tester.pumpAndSettle();
      expect(find.text('Bật auto xem và bình luận'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

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
      final controller = _TestController(WebUri(page.initialUrl), steps: [
        'verification-requested',
        'waiting-otp',
        'otp-submitted',
        action == TikTokLaunchAction.login ? 'login-success' : 'signup-success',
      ]);
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onWebViewCreated!.call(wrapped);
      params.onLoadStop!.call(wrapped, controller.url);
      await tester.pump();
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
      }
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      final sources =
          controller.sources.where((source) => source.contains(step));
      expect(sources, hasLength(4));
      expect(
          sources.first,
          contains(
              '"otp":"${action == TikTokLaunchAction.login ? '654321' : '012345'}"'));
      expect(sources.first, contains('"otpRequestedAt":null'));
      expect(sources.elementAt(1), isNot(contains('"otpRequestedAt":null')));
      expect(sources.last, contains('"allowOtpSubmit":false'));
      expect(
          find.text(action == TikTokLaunchAction.login
              ? 'Đăng nhập TikTok thành công.'
              : 'Đăng ký TikTok thành công.'),
          findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  }

  for (final action in [TikTokLaunchAction.login, TikTokLaunchAction.signup]) {
    testWidgets(
        '$action fetches OTP once after request and pastes the API code',
        (tester) async {
      final reader = _TestOtpReader();
      final clipboard = <String>[];
      tester.binding.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') {
          clipboard.add(call.arguments['text'] as String);
        }
        return null;
      });
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        const MethodChannel('test_tiktok/comment_input'),
        (call) async => true,
      );
      addTearDown(() {
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, null);
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('test_tiktok/comment_input'), null);
      });
      final controller = await _mountApiPage(tester, action, reader, [
        'waiting-form',
        'verification-requested',
        ...List.generate(400, (_) => 'otp-required'),
      ]);
      await tester.pump(const Duration(milliseconds: 800));
      expect(reader.requests, isEmpty);
      await tester.pump(const Duration(milliseconds: 800));
      expect(reader.requests, [
        (
          action == TikTokLaunchAction.login
              ? 'login@example.com'
              : 'signup@example.com',
          'mail-secret'
        )
      ]);
      await tester.pump(const Duration(seconds: 60));
      await tester.pump(const Duration(seconds: 60));
      expect(reader.requests, hasLength(1));
      expect(find.text('Dừng'), findsOneWidget);
      reader.response.complete('012345');
      controller.steps!
        ..clear()
        ..addAll([
          'waiting-paste',
          'otp-submitted',
          action == TikTokLaunchAction.login
              ? 'login-success'
              : 'signup-success'
        ]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      final source =
          controller.sources.lastWhere((source) => source.contains(step));
      expect(source, contains('"otp":"012345"'));
      expect(source, isNot(contains('mail-secret')));
      expect(source, isNot(contains('test-reader-token')));
      final handler = controller.handlers[action == TikTokLaunchAction.login
          ? 'FlutterLoginPaste'
          : 'FlutterSignupPaste']!;
      expect(await handler([1, 'otp']), true);
      expect(clipboard, ['012345']);
      for (var i = 0; i < 2; i++) {
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
      }
      expect(reader.requests, hasLength(1));
      expect(reader.closed, isTrue);
      expect(
          find.text(action == TikTokLaunchAction.login
              ? 'Đăng nhập TikTok thành công.'
              : 'Đăng ký TikTok thành công.'),
          findsOneWidget);
    });

    testWidgets('$action ignores an API response after Stop', (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
          tester, action, reader, List.generate(10, (_) => 'otp-required'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(reader.requests, hasLength(1));
      await tester.tap(find.text('Dừng'));
      await tester.pump();
      expect(reader.closed, isTrue);
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      final evaluated =
          controller.sources.where((source) => source.contains(step)).length;
      reader.response.complete('012345');
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      expect(controller.sources.where((source) => source.contains(step)),
          hasLength(evaluated));
      final handler = controller.handlers[action == TikTokLaunchAction.login
          ? 'FlutterLoginPaste'
          : 'FlutterSignupPaste']!;
      expect(await handler([1, 'otp']), false);
    });

    testWidgets('$action reports an API error without entering an OTP',
        (tester) async {
      final reader = _TestOtpReader();
      final controller = await _mountApiPage(
          tester, action, reader, ['verification-requested', 'otp-required']);
      await tester.pump(const Duration(milliseconds: 800));
      reader.response
          .completeError(const OtpApiException('API chưa tìm thấy mã.'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.text('API chưa tìm thấy mã.'), findsOneWidget);
      expect(reader.closed, isTrue);
      final step = action == TikTokLaunchAction.login
          ? autoLoginStepScript
          : autoSignupStepScript;
      expect(controller.sources.where((source) => source.contains(step)),
          hasLength(1));
    });

    testWidgets('$action still detects CAPTCHA while API is pending',
        (tester) async {
      final reader = _TestOtpReader();
      await _mountApiPage(tester, action, reader,
          ['verification-requested', 'verification-required']);
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump(const Duration(milliseconds: 800));
      await tester.pump();
      expect(reader.closed, isTrue);
      expect(
          find.text(action == TikTokLaunchAction.login
              ? 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. Hãy hoàn tất trên trang đăng nhập.'
              : 'TikTok yêu cầu CAPTCHA hoặc mã xác minh. Hãy hoàn tất trên trang đăng ký.'),
          findsOneWidget);
      reader.response.complete('012345');
      await tester.pump();
    });
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final action in [
      TikTokLaunchAction.login,
      TikTokLaunchAction.signup
    ]) {
      testWidgets('$platform $action pastes credentials and OTP natively',
          (tester) async {
        debugDefaultTargetPlatformOverride = platform;
        final previousPlatform = InAppWebViewPlatform.instance;
        InAppWebViewPlatform.instance = _TestWebViewPlatform();
        final clipboard = <String>[];
        final nativePastes = <MethodCall>[];
        tester.binding.defaultBinaryMessenger
            .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard.add(call.arguments['text'] as String);
          }
          return null;
        });
        tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
            const MethodChannel('test_tiktok/comment_input'), (call) async {
          nativePastes.add(call);
          return true;
        });
        addTearDown(() {
          debugDefaultTargetPlatformOverride = null;
          if (previousPlatform != null) {
            InAppWebViewPlatform.instance = previousPlatform;
          }
          tester.binding.defaultBinaryMessenger
              .setMockMethodCallHandler(SystemChannels.platform, null);
          tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
              const MethodChannel('test_tiktok/comment_input'), null);
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
        final controller = _TestController(WebUri(page.initialUrl),
            steps: List.generate(10, (_) => 'waiting-paste'));
        final wrapped =
            InAppWebViewController.fromPlatform(platform: controller);
        params.onWebViewCreated!.call(wrapped);
        params.onLoadStop!.call(wrapped, controller.url);
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 800));
        await tester.pump();
        final paste = controller
            .handlers[signup ? 'FlutterSignupPaste' : 'FlutterLoginPaste']!;
        expect(await paste([99, 'email']), false);
        expect(await paste([1, 'unknown']), false);
        expect(clipboard, isEmpty);
        for (final field in ['email', 'password', 'otp']) {
          expect(await paste([1, field]), true);
        }
        expect(
            clipboard,
            signup
                ? ['signup@example.com', 'signup-secret', '012345']
                : ['login-user', 'login-secret', '654321']);
        expect(nativePastes, hasLength(3));
        for (final call in nativePastes) {
          expect(call.method, 'paste');
          expect(call.arguments,
              {'context': signup ? 'signup' : 'login', 'attempt': 1});
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(milliseconds: 800));
        expect(await paste([1, 'otp']), false);
        expect(nativePastes, hasLength(3));
        debugDefaultTargetPlatformOverride = null;
        expect(tester.takeException(), isNull);
      });
    }
  }
}

Future<void> _selectHomeTab(WidgetTester tester, String key) async {
  final tab = find.byKey(Key(key));
  await tester.ensureVisible(tab);
  await tester.tap(tab);
  await tester.pumpAndSettle();
}

Future<_TestController> _mountApiPage(
    WidgetTester tester,
    TikTokLaunchAction action,
    _TestOtpReader reader,
    List<String> steps) async {
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
          readerToken: 'test-reader-token'),
    ),
  );
  await tester.pumpWidget(MaterialApp(home: page));
  final params =
      tester.widget<InAppWebView>(find.byType(InAppWebView)).platform.params;
  final controller = _TestController(WebUri(page.initialUrl), steps: steps);
  final wrapped = InAppWebViewController.fromPlatform(platform: controller);
  params.onWebViewCreated!.call(wrapped);
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
            const PlatformInAppWebViewControllerCreationParams(id: 0));

  final WebUri url;
  final List<String>? steps;
  final sources = <String>[];
  final handlers = <String, JavaScriptHandlerCallback>{};

  @override
  Future<WebUri?> getUrl() async => url;

  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    sources.add(source);
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
