import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/auto_watch_script.dart';

void main() {
  for (final persistent in [false, true]) {
    testWidgets(
      persistent
          ? 'stops when verification persists after pasting signup OTP'
          : 'continues to password when verification is transient after signup OTP',
      (tester) async {
        var now = DateTime(2026, 10, 14);
        final view = _SignupView();
        final notices = <String>[];
        final reader = _OtpReader();
        final logic = TikTokController(
          configuration: AppConfiguration(
            userAgent: 'test-agent',
            comments: [],
            signupEmail: '',
            signupPassword: '',
            loginUsername: '',
            loginPassword: '',
            signupMailboxPassword: 'mail-password',
            otpApi: OtpApiConfiguration(
              url: Uri.parse('https://example.com/api/code'),
              readerToken: 'test-token',
            ),
          ),
          useAccessibility: false,
          otpReaderFactory: (_) => reader,
          now: () => now,
        )..onInit();
        logic.webViewController = InAppWebViewController.fromPlatform(
          platform: view,
        );
        logic.onNotice = (notice) => notices.add(notice.message);
        addTearDown(logic.onClose);
        final signup = logic.autoSignup();
        await tester.pump();

        Future<void> step(String result, {int milliseconds = 300}) async {
          view.nextStep = result;
          now = now.add(Duration(milliseconds: milliseconds));
          await tester.pump(const Duration(seconds: 10));
          await tester.pump();
        }

        await step('waiting-manual-email');
        expect(
          view.sources.last,
          contains('"manualAccessibilityButtons":false'),
        );
        expect(view.sources.last, contains('"manualFieldInput":true'));
        expect(logic.signupStatus, 'Hãy nhập email trên TikTok.');
        expect(logic.signupOtpRequest, isNull);
        await step('verification-requested');
        await step('waiting-manual-otp');
        expect(logic.signupStatus, 'Hãy nhập đủ 6 số OTP trên TikTok.');
        expect(logic.autoSignupBusy, isTrue);
        expect(reader.requests, 0);
        await step('otp-submitted');
        await step('verification-required');
        expect(logic.autoSignupBusy, isTrue);
        expect(notices, isEmpty);
        // Poll fast through the transition without touching the OTP again.
        await step('verification-required');
        expect(logic.autoSignupBusy, isTrue);

        if (persistent) {
          await step('verification-required', milliseconds: 1600);
          await signup;
          expect(logic.autoSignupBusy, isFalse);
          expect(notices.single, contains('CAPTCHA hoặc mã xác minh'));
          expect(view.stopCalls, 1);
        } else {
          await step('waiting-password-screen');
          await step('waiting-next');
          await step('waiting-manual-password');
          expect(logic.autoSignupBusy, isTrue);
          expect(view.sources.last, contains('"allowPasswordSubmit":true'));
          expect(logic.signupStatus, 'Hãy nhập mật khẩu trên TikTok.');
          await step('password-submitted');
          await step('username-skipped');
          await step('signup-success');
          await signup;
          expect(notices, ['Đăng ký TikTok thành công.']);
          expect(view.watchStarted, isFalse);
          expect(logic.autoWatchEnabled, isFalse);
          expect(view.stopCalls, 1);
        }
        expect(reader.requests, 0);
        logic.onClose();
      },
    );
  }
}

class _SignupView extends PlatformInAppWebViewController {
  _SignupView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String nextStep = 'waiting-form';
  final sources = <String>[];
  int stopCalls = 0;
  bool watchStarted = false;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoSignupStepScript)) {
      sources.add(source);
      return nextStep;
    }
    if (source.contains(autoWatchStartScript)) watchStarted = true;
    if (source.contains('__flutterAutoSignup.stop()')) stopCalls++;
    return true;
  }
}

class _OtpReader implements OtpCodeReader {
  int requests = 0;
  @override
  Future<String> fetchCode({
    required String email,
    required String password,
  }) async {
    requests++;
    return '012345';
  }

  @override
  void close() {}
}
