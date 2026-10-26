import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/browser_view.dart';
import 'package:test_tiktok/core/rotate_captcha.dart';
import 'package:test_tiktok/core/scripts/rotate_captcha_script.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

class _FailedVerification extends RotateCaptchaSolver {
  final failure = Completer<bool>();
  int calls = 0;
  int? requestedAttempts;

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
    requestedAttempts = attempts;
    return failure.future;
  }
}

class _Controller extends TikTokController {
  _Controller(
    CaptchaSettingsStore settings,
    List<TikTokFlowResult> results,
    _FailedVerification solver, {
    bool automatic = true,
  }) : super(
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
         autoAdvance: automatic,
         onFlowFinished: results.add,
       );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browserChannel = MethodChannel('test_tiktok/browser_view_73');
  const accessibilityChannel = MethodChannel('x-slayer/accessibility_channel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  dynamic present;
  bool failInspection = false;
  String url = '';
  final calls = <String>[];

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    RemoteConfig.configs = {
      ...RemoteConfig.defaults,
      'sadcaptcha_license_key': 'fixture-key',
    };
    present = true;
    failInspection = false;
    url = 'https://www.tiktok.com/search?q=fixture';
    calls.clear();
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'getUrl') return url;
      if (call.method == 'evaluateJavascript') {
        if (failInspection) {
          throw PlatformException(
            code: 'javascript_error',
            message: 'Bridge not ready',
          );
        }
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

  for (final automatic in [false, true]) {
    testWidgets(
      'CAPTCHA failure handles concurrent readers (automatic=$automatic)',
      (tester) async {
        final results = <TikTokFlowResult>[];
        final notices = <String>[];
        final settings = CaptchaSettingsStore();
        await settings.load();
        final solver = _FailedVerification();
        final logic = _Controller(
          settings,
          results,
          solver,
          automatic: automatic,
        )..onInit();
        final browser = BrowserController.test(73);
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
        expect(solver.requestedAttempts, 3);
        await tester.pump(const Duration(seconds: 8));
        expect(logic.verificationPaused, isFalse);
        expect(results, isEmpty);
        solver.failure.completeError(
          StateError('Chưa đọc được CAPTCHA sau thời gian chờ.'),
        );
        await tester.pump();
        await Future.wait([first, second]);
        expect(logic.verificationPaused, !automatic);
        expect(logic.autoWatchEnabled, isFalse);
        expect(logic.loginConfirmed, isTrue);
        expect(notices, hasLength(1));
        expect(
          notices.single,
          automatic
              ? contains('Chuyển cấu hình')
              : contains(TikTokController.verificationPausedMessage),
        );
        expect(notices.single, contains('Chưa đọc được CAPTCHA'));
        expect(notices.single, isNot(contains('3 lần')));
        expect(results, isEmpty);
        await tester.pump(TikTokController.autoFailureDelay);
        expect(results, automatic ? [TikTokFlowResult.failed] : isEmpty);
        await tester.pump(const Duration(hours: 1));
        expect(results, automatic ? [TikTokFlowResult.failed] : isEmpty);
        expect(calls, isNot(contains('loadUrl')));
        expect(calls, isNot(contains('reload')));
        logic.onDelete();
        await tester.pump();
        browser.dispose();
        settings.dispose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final mode in ['absent', 'null', 'string-null', 'bridge-error']) {
    testWidgets('does not fail a configuration when CAPTCHA is $mode', (
      tester,
    ) async {
      final results = <TikTokFlowResult>[];
      final notices = <String>[];
      final settings = CaptchaSettingsStore();
      await settings.load();
      final solver = _FailedVerification();
      final logic = _Controller(settings, results, solver)..onInit();
      final browser = BrowserController.test(73);
      await logic.onWebViewCreated(browser);
      logic.onNotice = (notice) => notices.add(notice.message);
      logic.autoWatchEnabled = true;
      logic.loginConfirmed = true;
      present = mode == 'absent'
          ? false
          : mode == 'string-null'
          ? 'null'
          : null;
      failInspection = mode == 'bridge-error';

      final checking = logic.signupAccessibility.beforeSnapshot!();
      await checking;
      await tester.pump(TikTokController.autoFailureDelay);
      expect(solver.calls, 0);
      expect(logic.autoWatchEnabled, isTrue);
      expect(logic.verificationPaused, isFalse);
      expect(results, isEmpty);
      expect(notices, isEmpty);

      // A later confirmed challenge still reaches the solver.
      present = true;
      failInspection = false;
      final retry = expectLater(
        logic.signupAccessibility.beforeSnapshot!(),
        throwsA(isA<RotateCaptchaCancelled>()),
      );
      await tester.pump();
      expect(solver.calls, 1);
      solver.failure.completeError(RotateCaptchaCancelled());
      await retry;
      logic.onDelete();
      await tester.pump();
      browser.dispose();
      settings.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('does not fail when CAPTCHA disappears during solving', (
    tester,
  ) async {
    final results = <TikTokFlowResult>[];
    final settings = CaptchaSettingsStore();
    await settings.load();
    final solver = _FailedVerification();
    final logic = _Controller(settings, results, solver)..onInit();
    final browser = BrowserController.test(73);
    await logic.onWebViewCreated(browser);
    logic.autoWatchEnabled = true;
    final checking = logic.signupAccessibility.beforeSnapshot!();
    await tester.pump();
    expect(solver.calls, 1);
    present = false;
    solver.failure.completeError(
      StateError('Chưa đọc được CAPTCHA sau thời gian chờ.'),
    );
    await checking;
    await tester.pump(TikTokController.autoFailureDelay);
    expect(logic.autoWatchEnabled, isTrue);
    expect(results, isEmpty);
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
