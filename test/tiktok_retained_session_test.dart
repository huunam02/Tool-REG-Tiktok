import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/account_sessions.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/configuration_data.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/gecko_browser.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';
import 'package:test_tiktok/core/tiktok_flow_result.dart';
import 'package:test_tiktok/core/tiktok_launch_action.dart';

import 'support/memory_nurture_store.dart';
import 'support/memory_proxy_store.dart';

/// The live TikTok page: its sidebar shows Messages/Profile once signed in.
class _Accessibility extends SignupAccessibility {
  bool signedIn = true;
  final Map<String, dynamic> feed = Map<String, dynamic>.from(
    jsonDecode(
          File(
            'test/fixtures/nurture_accessibility_recording.json',
          ).readAsStringSync(),
        )['feed']
        as Map,
  );

  Map<String, dynamic> _label(String id, String text) => {
    'id': id,
    'bounds': [0, 0, 40, 40],
    'text': text,
    'clickable': true,
    'enabled': true,
  };

  @override
  Future<SignupSnapshot> snapshot() async => SignupSnapshot({
    ...feed,
    'nodes': [
      ...(feed['nodes'] as List),
      if (signedIn) ...[
        _label('sidebar.messages', 'Messages'),
        _label('sidebar.profile', 'Profile'),
      ] else
        _label('sidebar.login', 'Log in'),
    ],
  });

  @override
  Future<void> cancelPaste() async {}

  // The recorded feed never moves; gestures complete without effect.
  @override
  Future<void> swipe(SignupViewport viewport, Offset from, Offset to) async {}
  @override
  Future<void> tap(SignupViewport viewport, Offset point) async {}
}

class _Controller extends TikTokController {
  _Controller(
    this.accessibility, {
    required super.configuration,
    super.proxyStore,
    super.captchaSettingsStore,
    super.startWithNurture,
    super.autoAdvance,
    super.onFlowFinished,
    super.now,
  }) : super(
         launchAction: TikTokLaunchAction.login,
         useAccessibility: true,
         nurtureProfileLoader: () async => NurtureCoordinateProfile({}),
       );
  final _Accessibility accessibility;
  @override
  SignupAccessibility get signupAccessibility => accessibility;
}

class _LoginProbeController extends _Controller {
  _LoginProbeController(
    super.accessibility, {
    required super.configuration,
    required super.proxyStore,
    required super.captchaSettingsStore,
    super.now,
    super.startWithNurture,
  });

  int loginCalls = 0;
  final loginStates = <List<bool>>[];

  @override
  Future<void> autoLogin() async {
    loginCalls++;
    loginStates.add([autoWatchEnabled, loginConfirmed, autoWatchBusy]);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_tiktok/gecko_view_84');
  final calls = <MethodCall>[];

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    calls.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
          calls.add(call);
          if (call.method == 'getUrl') return 'https://www.tiktok.com/';
          if (call.method == 'evaluateJavascript') return null;
          return null;
        });
  });

  for (final scenario in ['missing', 'expired', 'nurture-entry']) {
    testWidgets('$scenario session logs in before enabling nurture', (
      tester,
    ) async {
      final accessibility = _Accessibility()..signedIn = false;
      final store = MemoryProxyStore()
        ..currentId = 1
        ..currentAccount = const AccountCredentials(
          email: 'person@example.com',
          password: 'fixture',
          dataMail: 'fixture-mail',
        )
        ..currentAccountLoggedIn = scenario == 'expired';
      if (scenario == 'expired') {
        // A saved hint must not override a logged-out live TikTok page.
        await AccountSessions.save(1, 'person@example.com');
      }
      final settings = CaptchaSettingsStore();
      await settings.load();
      final logic = _LoginProbeController(
        accessibility,
        configuration: AppConfiguration(
          configurationId: 1,
          userAgent: 'fixture',
          comments: const [],
          signupEmail: '',
          signupPassword: '',
          loginUsername: 'person@example.com',
          loginPassword: 'fixture',
        ),
        proxyStore: store,
        captchaSettingsStore: settings,
        startWithNurture: scenario == 'nurture-entry',
        now: tester.binding.clock.now,
      )..onInit();
      final browser = GeckoController.test(84);
      await logic.onWebViewCreated(browser);
      logic.initialPageLoaded = true;
      final action = logic.runInitialAction();
      await tester.pump();
      if (scenario != 'missing') {
        expect(logic.loginCalls, 0);
        for (var i = 0; i < 20; i++) {
          expect(logic.autoWatchEnabled, isFalse);
          await tester.pump(const Duration(milliseconds: 500));
        }
      }
      await action;
      expect(logic.loginCalls, 1);
      expect(logic.loginStates, [
        [false, false, false],
      ]);
      expect(logic.autoWatchEnabled, isFalse);
      expect(store.currentAccountLoggedIn, isFalse);
      expect(await AccountSessions.currentIsLoggedIn(), isFalse);
      // Page hydration, reload completion or resume cannot start a duplicate login.
      await logic.runInitialAction();
      expect(logic.loginCalls, 1);
      logic.onDelete();
      await tester.pump();
      browser.dispose();
      settings.dispose();
    });
  }

  testWidgets('missing login credentials never start nurture', (tester) async {
    final store = MemoryProxyStore();
    final settings = CaptchaSettingsStore();
    await settings.load();
    final notices = <String>[];
    final logic = _Controller(
      _Accessibility()..signedIn = false,
      configuration: AppConfiguration(
        userAgent: 'fixture',
        comments: const [],
        signupEmail: '',
        signupPassword: '',
        loginUsername: 'person@example.com',
        loginPassword: '',
      ),
      proxyStore: store,
      captchaSettingsStore: settings,
    )..onInit();
    logic.onNotice = (notice) => notices.add(notice.message);
    final browser = GeckoController.test(84);
    await logic.onWebViewCreated(browser);
    logic.initialPageLoaded = true;
    await logic.runInitialAction();
    expect(
      notices,
      contains('Hãy nhập tài khoản và mật khẩu đăng nhập ở màn Cấu hình.'),
    );
    expect(logic.loginConfirmed, isFalse);
    expect(logic.autoWatchEnabled, isFalse);
    logic.onDelete();
    await tester.pump();
    browser.dispose();
    settings.dispose();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
  });

  for (final automatic in [false, true]) {
    testWidgets(
      '${automatic ? 'queued' : 'single'} nurture completes and retains login after an hour',
      (tester) async {
        final store = MemoryProxyStore()
          ..currentId = 1
          ..currentAccount = const AccountCredentials(
            email: 'person@example.com',
            password: 'fixture',
            dataMail: 'fixture-mail',
          )
          ..currentAccountLoggedIn = true;
        final settings = CaptchaSettingsStore();
        await settings.load();
        final results = <TikTokFlowResult>[];
        final logic = _Controller(
          _Accessibility(),
          configuration: AppConfiguration(
            configurationId: 1,
            userAgent: 'fixture',
            comments: const [],
            signupEmail: '',
            signupPassword: '',
            loginUsername: 'person@example.com',
            loginPassword: 'fixture',
            nurtureSettings: const NurtureSettings(
              minMinutes: 2,
              maxMinutes: 2,
            ),
          ),
          startWithNurture: true,
          autoAdvance: automatic,
          proxyStore: store,
          captchaSettingsStore: settings,
          onFlowFinished: results.add,
          now: tester.binding.clock.now,
        )..onInit();
        final browser = GeckoController.test(84);
        await logic.onWebViewCreated(browser);
        logic.initialPageLoaded = true;
        await logic.runInitialAction();
        expect(logic.autoWatchEnabled, isTrue);
        expect(logic.loginConfirmed, isTrue);
        expect(results, isEmpty);

        await tester.pump(const Duration(minutes: 2));
        expect(results, [TikTokFlowResult.nurtureCompleted]);
        expect(logic.autoWatchEnabled, isFalse);
        // The recorded feed never plays; screen time still counts in full.
        final nurture = store.nurture as MemoryNurtureRepository;
        expect(nurture.phases.values, ['completed']);
        expect(
          nurture.totals.values.single.watchMilliseconds,
          const Duration(minutes: 2).inMilliseconds,
        );
        await tester.pump(const Duration(hours: 1));
        expect(results, [TikTokFlowResult.nurtureCompleted]);
        expect(logic.loginConfirmed, isTrue);
        expect(store.currentAccountLoggedIn, isTrue);
        expect(await AccountSessions.currentIsLoggedIn(), isTrue);
        expect(calls.where((call) => call.method == 'loadUrl'), isEmpty);
        expect(
          calls
              .where((call) => call.method == 'evaluateJavascript')
              .map((call) => (call.arguments as Map)['source'] as String),
          everyElement(isNot(contains('__flutterAutoLogout'))),
        );
        logic.onDelete();
        await tester.pump();
        browser.dispose();
        settings.dispose();
      },
    );
  }
}
