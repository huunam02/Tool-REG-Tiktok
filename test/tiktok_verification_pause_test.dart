import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/gecko_browser.dart';
import 'package:test_tiktok/core/rotate_captcha.dart';
import 'package:test_tiktok/core/scripts/rotate_captcha_script.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

class _FailedVerification extends RotateCaptchaSolver {
  final failure = Completer<bool>();
  int calls = 0;

  @override
  Future<bool> solve({
    required String licenseKey,
    required Future<RotateCaptchaChallenge?> Function() read,
    required SignupAccessibility accessibility,
    required Future<bool> Function() isPresent,
    required Future<void> Function() guard,
    required void Function(String) onStatus,
    Future<void> Function()? refresh,
    int attempts = 3,
  }) {
    calls++;
    return failure.future;
  }
}

class _Controller extends TikTokController {
  _Controller(
    CaptchaSettingsStore settings,
    List<TikTokFlowResult> results,
    _FailedVerification solver,
  ) : super(
        configuration: AppConfiguration(
          userAgent: 'fixture',
          comments: const [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: '',
          loginPassword: '',
        ),
        launchAction: TikTokLaunchAction.login,
        useAccessibility: true,
        captchaSettingsStore: settings,
        rotateCaptchaSolverFactory: () => solver,
        autoAdvance: true,
        onFlowFinished: results.add,
      );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browserChannel = MethodChannel('test_tiktok/gecko_view_73');
  const accessibilityChannel = MethodChannel('x-slayer/accessibility_channel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  dynamic present;
  String url = '';
  final calls = <String>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    RemoteConfig.configs = {
      ...RemoteConfig.defaults,
      'sadcaptcha_license_key': 'fixture-key',
    };
    present = true;
    url = 'https://www.tiktok.com/search?q=fixture';
    calls.clear();
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'getUrl') return url;
      if (call.method == 'evaluateJavascript') {
        final source = (call.arguments as Map)['source'];
        if (source == rotateCaptchaPresentScript) return present;
        if (source == readRotateCaptchaScript) return null;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(accessibilityChannel, (call) async {
      if (call.method == 'isAccessibilityPermissionEnabled') return true;
      return null;
    });
  });

  tearDown(() {
    messenger.setMockMethodCallHandler(browserChannel, null);
    messenger.setMockMethodCallHandler(accessibilityChannel, null);
    RemoteConfig.configs = RemoteConfig.defaults;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('CAPTCHA failure pauses concurrent readers and keeps the page', (
    tester,
  ) async {
    final results = <TikTokFlowResult>[];
    final notices = <String>[];
    final settings = CaptchaSettingsStore();
    await settings.load();
    final solver = _FailedVerification();
    final logic = _Controller(settings, results, solver)..onInit();
    final browser = GeckoController.test(73);
    await logic.onWebViewCreated(browser);
    logic.onNotice = (notice) => notices.add(notice.message);
    logic.autoWatchEnabled = true;
    logic.loginConfirmed = true;

    final first = expectLater(
      logic.signupAccessibility.snapshot(),
      throwsA(isA<RotateCaptchaCancelled>()),
    );
    final second = expectLater(
      logic.signupAccessibility.snapshot(),
      throwsA(isA<RotateCaptchaCancelled>()),
    );
    await tester.pump();
    expect(solver.calls, 1);
    await tester.pump(const Duration(seconds: 8));
    expect(logic.verificationPaused, isFalse);
    expect(results, isEmpty);
    solver.failure.completeError(
      StateError('Chưa đọc được CAPTCHA sau thời gian chờ.'),
    );
    await tester.pump();
    await Future.wait([first, second]);
    expect(logic.verificationPaused, isTrue);
    expect(logic.autoWatchEnabled, isFalse);
    expect(logic.loginConfirmed, isTrue);
    expect(notices, [TikTokController.verificationPausedMessage]);
    // Neither the failure delay nor watchdog may return to Home while verification is pending.
    await tester.pump(const Duration(hours: 1));
    expect(results, isEmpty);
    expect(calls, isNot(contains('loadUrl')));
    expect(calls, isNot(contains('reload')));
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
