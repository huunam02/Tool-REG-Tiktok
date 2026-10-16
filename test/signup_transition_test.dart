import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
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
        final logic = TikTokController(
          configuration: AppConfiguration(
            userAgent: 'test-agent',
            comments: [],
            signupEmail: 'signup@example.com',
            signupPassword: 'signup-password',
            loginUsername: '',
            loginPassword: '',
            signupMailboxPassword: 'mail-password',
            otpApi: OtpApiConfiguration(
              url: Uri.parse('https://example.com/api/code'),
              readerToken: 'test-token',
            ),
          ),
          useAccessibility: false,
          otpReaderFactory: (_) => _OtpReader(),
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

        await step('verification-requested');
        await step('waiting-otp-paste');
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
          await step('waiting-password-submit');
          expect(logic.autoSignupBusy, isTrue);
          expect(view.sources.last, contains('"allowPasswordSubmit":true'));
          await step('password-submitted');
          await step('signup-success');
          await signup;
          expect(notices, ['Đăng ký TikTok thành công.']);
          expect(view.watchStarted, isFalse);
          expect(logic.waitingToAutoWatch, isTrue);
          expect(view.stopCalls, 1);
        }
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
  @override
  Future<String> fetchCode({
    required String email,
    required String password,
  }) async => '012345';

  @override
  void close() {}
}
