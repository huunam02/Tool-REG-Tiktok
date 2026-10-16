import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';

void main() {
  for (final submittedAt in [42, 119]) {
    testWidgets(
      'slow login submitted at ${submittedAt}s still selects Email and fetches OTP',
      (tester) async {
        final started = DateTime(2026, 10, 14);
        var now = started;
        final webView = _LoginView();
        final reader = _OtpReader();
        final notices = <String>[];
        final logic = TikTokController(
          configuration: _configuration(),
          otpReaderFactory: (_) => reader,
          now: () => now,
        )..onInit();
        logic.webViewController = InAppWebViewController.fromPlatform(
          platform: webView,
        );
        logic.onNotice = (notice) => notices.add(notice.message);
        addTearDown(logic.onClose);
        final login = logic.autoLogin();
        await tester.pump();

        Future<void> step(String result, int seconds) async {
          webView.nextStep = result;
          now = started.add(Duration(seconds: seconds));
          // Advance through the full randomized 2-10s polling interval. The
          // controller's deadline clock remains the explicit `now` above.
          await tester.pump(const Duration(seconds: 10));
          await tester.pump();
        }

        await step('waiting-paste', submittedAt - 3);
        expect(logic.autoLoginBusy, isTrue);
        await step('submitted', submittedAt);
        await step('waiting-result', submittedAt + 4);
        expect(logic.autoLoginBusy, isTrue);
        expect(reader.requests, isEmpty);
        await step('waiting-email-verification', submittedAt + 42);
        await step('requesting-email-verification', submittedAt + 47);
        expect(reader.requests, isEmpty);
        await step('email-verification-selected', submittedAt + 49);
        await step('requesting-verification', submittedAt + 50);
        expect(logic.autoLoginBusy, isTrue);
        expect(reader.requests, isEmpty);
        await step('verification-requested', submittedAt + 51);
        expect(reader.requests, [('login@example.com', 'mail-password')]);
        reader.response.complete('012345');
        await tester.pump();
        await step('waiting-otp-paste', submittedAt + 52);
        await step('otp-submitted', submittedAt + 53);
        await step('login-success', submittedAt + 54);
        await login;
        expect(logic.autoLoginBusy, isFalse);
        expect(notices, ['Đăng nhập TikTok thành công.']);
        expect(reader.requests, hasLength(1));
        expect(reader.closed, isTrue);
        expect(webView.sources.last, contains('"allowOtpSubmit":false'));
        logic.onClose();
      },
    );
  }

  testWidgets(
    'repeated submitted results do not extend the login wait forever',
    (tester) async {
      final started = DateTime(2026, 10, 14);
      var now = started;
      final webView = _LoginView()..nextStep = 'submitted';
      final reader = _OtpReader();
      final logic = TikTokController(
        configuration: _configuration(),
        otpReaderFactory: (_) => reader,
        now: () => now,
      )..onInit();
      logic.webViewController = InAppWebViewController.fromPlatform(
        platform: webView,
      );
      addTearDown(logic.onClose);
      final login = logic.autoLogin();
      await tester.pump();
      now = started.add(const Duration(seconds: 40));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      now = started.add(const Duration(seconds: 80));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(logic.autoLoginBusy, isTrue);
      now = started.add(const Duration(seconds: 86));
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      expect(logic.autoLoginBusy, isFalse);
      expect(reader.requests, isEmpty);
      await login;
    },
  );

  testWidgets('starts automatic video watching after login succeeds', (
    tester,
  ) async {
    final webView = _LoginView()..nextStep = 'login-success';
    final logic = TikTokController(configuration: _configuration())..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: webView,
    );
    addTearDown(logic.onClose);

    final login = logic.autoLogin();
    await tester.pump(const Duration(seconds: 10));
    await tester.pump();
    await login;

    expect(logic.autoWatchEnabled, isTrue);
    expect(webView.watchStarted, isTrue);
    logic.onClose();
  });
}

AppConfiguration _configuration() => AppConfiguration(
  userAgent: 'test-agent',
  comments: [],
  signupEmail: '',
  signupPassword: '',
  loginUsername: 'login@example.com',
  loginPassword: 'login-password',
  loginMailboxPassword: 'mail-password',
  otpApi: OtpApiConfiguration(
    url: Uri.parse('https://example.com/api/code'),
    readerToken: 'test-token',
  ),
);

class _LoginView extends PlatformInAppWebViewController {
  _LoginView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String nextStep = 'waiting-form';
  final sources = <String>[];
  bool watchStarted = false;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoLoginStepScript)) {
      sources.add(source);
      return nextStep;
    }
    if (source.contains(autoWatchStartScript)) watchStarted = true;
    return true;
  }
}

class _OtpReader implements OtpCodeReader {
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
