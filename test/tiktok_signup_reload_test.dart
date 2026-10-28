import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/gecko_browser.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_proxy_store.dart';

/// A half-rendered TikTok page: the desktop frame is readable, but no Log
/// in or Sign up control ever appears.
class _StuckPage extends SignupAccessibility {
  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot({
    'ready': true,
    'webBounds': [0, 1178, 1439, 1893],
    'nodes': [
      {
        'id': 'web',
        'bounds': [0, 1178, 1439, 1893],
        'enabled': true,
      },
    ],
  });

  @override
  Future<void> tap(SignupViewport viewport, Offset point) async =>
      fail('A stuck page must not be tapped.');
}

class _Controller extends TikTokController {
  _Controller({
    required super.configuration,
    super.proxyStore,
    super.captchaSettingsStore,
    super.now,
  }) : super(launchAction: TikTokLaunchAction.signup, useAccessibility: true);

  final _page = _StuckPage();
  @override
  SignupAccessibility get signupAccessibility => _page;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const browserChannel = MethodChannel('test_tiktok/gecko_view_85');
  const accessibilityChannel = MethodChannel('x-slayer/accessibility_channel');
  final calls = <String>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(browserChannel, (call) async {
      calls.add(call.method);
      if (call.method == 'getUrl') return 'https://www.tiktok.com/';
      return null;
    });
    messenger.setMockMethodCallHandler(accessibilityChannel, (call) async {
      if (call.method == 'isAccessibilityPermissionEnabled' ||
          call.method == 'isAccessibilityServiceRunning') {
        return true;
      }
      return null;
    });
  });

  tearDown(() {
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(browserChannel, null);
    messenger.setMockMethodCallHandler(accessibilityChannel, null);
  });

  testWidgets('a stuck signup page is reloaded once, then the attempt fails', (
    tester,
  ) async {
    final settings = CaptchaSettingsStore();
    await settings.load();
    final notices = <String>[];
    final logic = _Controller(
      configuration: AppConfiguration(
        userAgent: 'fixture',
        comments: const [],
        signupEmail: 'person@example.com',
        signupPassword: 'Example12!a',
        loginUsername: '',
        loginPassword: '',
      ),
      proxyStore: MemoryProxyStore(),
      captchaSettingsStore: settings,
      now: tester.binding.clock.now,
    )..onInit();
    logic.onNotice = (notice) => notices.add(notice.message);
    final browser = GeckoController.test(85);
    await logic.onWebViewCreated(browser);
    logic.initialPageLoaded = true;
    var finished = false;
    final run = logic.runInitialAction().whenComplete(() => finished = true);
    for (var i = 0; i < 400 && !finished; i++) {
      await tester.pump(const Duration(seconds: 1));
      // The reload completes like a real page load.
      if (calls.isNotEmpty && calls.last == 'reload') {
        calls.add('reloaded');
        logic.initialPageLoaded = true;
      }
    }
    await run;
    expect(calls.where((method) => method == 'reload'), hasLength(1));
    expect(logic.autoSignupBusy, isFalse);
    expect(
      notices.where((n) => n.contains('chưa ổn định')),
      hasLength(1),
      reason: '$notices',
    );
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
  });
}
