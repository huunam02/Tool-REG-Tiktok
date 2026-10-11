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
import 'package:test_tiktok/auto_login_script.dart';
import 'package:test_tiktok/auto_signup_script.dart';

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
    await tester.enterText(
        find.byKey(const Key('signupEmail')), 'signup@example.com');
    await tester.enterText(
        find.byKey(const Key('signupPassword')), 'signup-password');
    await tester.enterText(find.byKey(const Key('signupOtp')), '012345');
    await tester.enterText(
        find.byKey(const Key('loginUsername')), 'login-user');
    await tester.enterText(
        find.byKey(const Key('loginPassword')), 'login-password');
    await tester.enterText(find.byKey(const Key('loginOtp')), '654321');
    await tester.tap(find.byKey(const Key('signupBirthday')));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.edit_outlined));
    await tester.pumpAndSettle();
    await tester.enterText(
        find.descendant(
            of: find.byType(DatePickerDialog),
            matching: find.byType(TextFormField)),
        '02/29/2000');
    await tester.tap(find.text('Chọn'));
    await tester.pumpAndSettle();
    expect(find.text('2000-02-29'), findsOneWidget);
    expect(find.text('Chạy đăng nhập tự động'), findsOneWidget);
    expect(find.text('Chạy đăng ký tự động'), findsOneWidget);
    await tester.tap(find.byKey(const Key('openTikTok')));
    await tester.pumpAndSettle();
    final page = tester.widget<TikTokPage>(find.byType(TikTokPage));
    expect(page.launchAction, TikTokLaunchAction.browse);
    expect(page.configuration.birthday, DateTime(2000, 2, 29));
    expect(page.configuration.signupEmail, 'signup@example.com');
    expect(page.configuration.signupPassword, 'signup-password');
    expect(page.configuration.loginUsername, 'login-user');
    expect(page.configuration.loginPassword, 'login-password');
    expect(page.configuration.signupOtp, '012345');
    expect(page.configuration.loginOtp, '654321');
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
      await tester.tap(find.byKey(Key(entry.key)));
      await tester.pumpAndSettle();
      final automaticPage = tester.widget<TikTokPage>(find.byType(TikTokPage));
      expect(automaticPage.launchAction, entry.value);
      expect(automaticPage.configuration.signupEmail, 'signup@example.com');
      expect(automaticPage.configuration.loginUsername, 'login-user');
      expect(automaticPage.configuration.signupOtp, '012345');
      expect(automaticPage.configuration.loginOtp, '654321');
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
      tester.widget<TextFormField>(find.byKey(Key(key))).controller!.clear();
    }
    await tester.tap(find.byKey(const Key('runAutoLogin')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập tài khoản đăng nhập.'), findsOneWidget);
    expect(find.byType(TikTokPage), findsNothing);
    await tester.tap(find.byKey(const Key('runAutoSignup')));
    await tester.pumpAndSettle();
    expect(find.text('Nhập email đăng ký hợp lệ.'), findsOneWidget);
    expect(find.byType(TikTokPage), findsNothing);
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
        birthday: DateTime(2000, 2, 29),
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
      final wrapped = InAppWebViewController.fromPlatform(platform: controller);
      params.onWebViewCreated!.call(wrapped);
      expect(
          controller.sources, isEmpty); // Never run before the first page load.
      params.onLoadStop!.call(wrapped, controller.url);
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
