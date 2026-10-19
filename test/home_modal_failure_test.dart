import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/otp_api.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';
import 'package:test_tiktok/core/scripts/auto_signup_script.dart';
import 'package:test_tiktok/core/scripts/home_account_modal_script.dart';

void main() {
  for (final signup in [false, true]) {
    testWidgets(
      '${signup ? 'signup' : 'login'} stops with a notice when Home retries fail',
      (tester) async {
        final view = _HomeView();
        final notices = <String>[];
        var otpRequests = 0;
        final logic = TikTokController(
          configuration: AppConfiguration(
            userAgent: 'test-agent',
            comments: [],
            signupEmail: 'signup@example.com',
            signupPassword: 'signup-password',
            signupMailboxPassword: 'mail-password',
            loginUsername: 'login@example.com',
            loginPassword: 'login-password',
            loginMailboxPassword: 'mail-password',
            otpApi: OtpApiConfiguration(
              url: Uri.parse('http://127.0.0.1:3210/api/otp'),
              readerToken: 'test-token',
            ),
          ),
          useAccessibility: false,
          otpReaderFactory: (_) {
            otpRequests++;
            throw StateError('OTP must not start without a challenge');
          },
        )..onInit();
        logic.webViewController = InAppWebViewController.fromPlatform(
          platform: view,
        );
        logic.onNotice = (notice) => notices.add(notice.message);
        addTearDown(logic.onClose);

        final action = signup ? logic.autoSignup() : logic.autoLogin();
        await tester.pump();
        await tester.pump(const Duration(seconds: 10));
        await tester.pump();
        await action;

        expect(logic.autoLoginBusy, isFalse);
        expect(logic.autoSignupBusy, isFalse);
        expect(otpRequests, 0);
        expect(notices.single, contains('TikTok chưa mở hộp đăng nhập'));
        expect(view.source, contains(openHomeAccountModalScript));
      },
    );
  }
}

class _HomeView extends PlatformInAppWebViewController {
  _HomeView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );

  String? source;

  @override
  Future<WebUri?> getUrl() async => WebUri('https://www.tiktok.com/');

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains(autoLoginStepScript) ||
        source.contains(autoSignupStepScript)) {
      this.source = source;
      return 'home-modal-failed';
    }
    return true;
  }
}
