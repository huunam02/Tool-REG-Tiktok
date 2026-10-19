import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/captcha_settings_store.dart';
import 'package:test_tiktok/core/rotate_captcha.dart';
import 'package:test_tiktok/core/nurture_coordinate_profile.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/core/scripts/rotate_captcha_script.dart';
import 'package:test_tiktok/core/services/remote_config_service.dart';
import 'package:test_tiktok/core/signup_accessibility.dart';

class _View extends PlatformInAppWebViewController {
  _View()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  String path = '/', host = 'www.tiktok.com';
  bool captcha = false;
  String image = 'AQID';
  int reads = 0;
  @override
  Future<WebUri?> getUrl() async => WebUri('https://$host$path');
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source == readRotateCaptchaScript) {
      reads++;
      return captcha
          ? {
              'outer': 'data:image/png;base64,$image',
              'inner': 'data:image/png;base64,BAUG',
              'viewportWidth': 1000,
              'viewportHeight': 2000,
              'x': 200,
              'y': 500,
              'travel': 600,
            }
          : null;
    }
    if (source == rotateCaptchaPresentScript) return captcha;
    return true;
  }
}

class _Session {
  _Session({
    Future<http.Response> Function()? respond,
    bool watch = true,
    bool native = false,
    NurturePlan? manualPlan,
    CaptchaSettingsStore? captchaSettingsStore,
  }) {
    logic = TikTokController(
      configuration: AppConfiguration(
        userAgent: 'test',
        comments: ['Comment'],
        signupEmail: '',
        signupPassword: '',
        loginUsername: '',
        loginPassword: '',
      ),
      useAccessibility: true,
      useNativeWebView: native,
      manualViewingPlan: manualPlan,
      captchaSettingsStore: captchaSettingsStore,
      nurtureProfileLoader: () async => NurtureCoordinateProfile({}),
      rotateCaptchaSolverFactory: () => RotateCaptchaSolver(
        client: MockClient((request) {
          requests++;
          requestKeys.add(request.url.queryParameters['licenseKey']);
          return respond?.call() ??
              Future.value(http.Response('{"angle":180}', 200));
        }),
      ),
    )..onInit();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: view,
    );
    logic.loginConfirmed = true;
    logic.autoWatchEnabled = watch;
    logic.onLoadStart(
      logic.webViewController!,
      WebUri('https://www.tiktok.com/'),
    );
    logic.onNotice = (notice) => notices.add(notice.message);
  }
  late final TikTokController logic;
  final view = _View();
  int requests = 0, drags = 0, touches = 0;
  Completer<bool>? touchCompletion;
  Rect webBounds = const Rect.fromLTWH(0, 0, 400, 800);
  bool permission = true;
  final notices = <String>[];
  final requestKeys = <String?>[];

  Future<dynamic> native(MethodCall call) async {
    if (call.method == 'isAccessibilityPermissionEnabled') return permission;
    if (call.method == 'signupSnapshot') {
      return {
        'ready': true,
        'webBounds': [
          webBounds.left,
          webBounds.top,
          webBounds.right,
          webBounds.bottom,
        ],
      };
    }
    if (call.method == 'dispatchGesture') {
      final strokes = (call.arguments as Map)['strokes'] as List;
      if ((strokes.single['path'] as List).length == 2) {
        drags++;
        view.captcha = false;
      } else {
        touches++;
        if (touchCompletion != null) return touchCompletion!.future;
      }
    }
    return true;
  }
}

Future<void> _pumpSolve(WidgetTester tester) async {
  for (var i = 0; i < 20; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('x-slayer/accessibility_channel');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  setUp(() async {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    SharedPreferences.setMockInitialValues({});
    RemoteConfig.configs[RemoteConfigKey.sadcaptcha_license_key.name] =
        'fixture-key';
    await CaptchaSettingsStore.instance.load();
  });
  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    RemoteConfig.configs.remove(RemoteConfigKey.sadcaptcha_license_key.name);
    messenger.setMockMethodCallHandler(channel, null);
  });
  void attach(_Session session) {
    messenger.setMockMethodCallHandler(channel, session.native);
    addTearDown(() => session.logic.onDelete());
  }

  Future<void> finish(_Session session, WidgetTester tester) async {
    session.logic.onDelete();
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets(
    'ignores saved key, uses Remote Config and stops when remote key is cleared',
    (tester) async {
      SharedPreferences.setMockInitialValues({
        'sadcaptcha_license_key': 'saved-fixture-key',
      });
      final store = CaptchaSettingsStore();
      final session = _Session(captchaSettingsStore: store);
      attach(session);
      session.view.captcha = true;
      await session.logic.startAutoWatch();
      await _pumpSolve(tester);
      expect(session.requestKeys, ['fixture-key']);
      expect(session.drags, 1);

      RemoteConfig.configs[RemoteConfigKey.sadcaptcha_license_key.name] = '';
      await store.load();
      final reads = session.view.reads;
      session.view.captcha = true;
      await _pumpSolve(tester);
      expect(session.requests, 1);
      expect(session.view.reads, reads);
      await finish(session, tester);
      store.dispose();
    },
  );

  for (final mode in NurtureMode.values) {
    testWidgets('CAPTCHA monitoring covers ${mode.label}', (tester) async {
      final session = _Session();
      attach(session);
      final plan = NurturePlan(
        mode,
        mode == NurtureMode.search ? 'Travel' : '',
      );
      session.view.path = plan.initialUrl.replaceFirst(
        'https://www.tiktok.com',
        '',
      );
      await session.logic.startAutoWatch();
      await tester.pump(const Duration(seconds: 3));
      expect(session.view.reads, greaterThan(0));
      expect(session.requests, 0);
      final paths = [
        session.view.path,
        mode == NurtureMode.search ? '/@fixture/video/123' : '/@fixture',
      ];
      for (final path in paths) {
        session.view.path = path;
        session.view.captcha = true;
        await _pumpSolve(tester);
      }
      expect(session.requests, 2);
      expect(session.drags, 2);
      expect(session.logic.autoWatchEnabled, isTrue);
      await finish(session, tester);
    });
  }

  testWidgets('normal actions wait for one shared CAPTCHA solve', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final session = _Session(respond: () => response.future);
    attach(session);
    await session.logic.startAutoWatch();
    session.view.captcha = true;
    await tester.pump(const Duration(seconds: 1));
    final touch = session.logic.signupAccessibility.tap(
      SignupViewport(const Rect.fromLTWH(0, 0, 400, 800)),
      const Offset(100, 200),
    );
    await tester.pump();
    expect(session.touches, 0);
    response.complete(http.Response('{"angle":180}', 200));
    await _pumpSolve(tester);
    await touch;
    expect(session.requests, 1);
    expect(session.drags, 1);
    expect(session.touches, 1);
    await finish(session, tester);
  });

  testWidgets('monitor waits for native input already in progress', (
    tester,
  ) async {
    final session = _Session();
    attach(session);
    await session.logic.startAutoWatch();
    session.touchCompletion = Completer<bool>();
    final touch = session.logic.signupAccessibility.tap(
      SignupViewport(const Rect.fromLTWH(0, 0, 400, 800)),
      const Offset(100, 200),
    );
    await tester.pump();
    session.view.captcha = true;
    await tester.pump(const Duration(seconds: 1));
    expect(session.requests, 0);
    session.touchCompletion!.complete(true);
    await touch;
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.drags, 1);
    await finish(session, tester);
  });

  testWidgets('Stop cancels pending API, queued touch and future polling', (
    tester,
  ) async {
    final response = Completer<http.Response>();
    final session = _Session(respond: () => response.future);
    attach(session);
    await session.logic.startAutoWatch();
    session.view.captcha = true;
    await tester.pump(const Duration(seconds: 1));
    expect(session.requests, 1);
    final touch = session.logic.signupAccessibility.tap(
      SignupViewport(const Rect.fromLTWH(0, 0, 400, 800)),
      const Offset(100, 200),
    );
    final rejected = expectLater(touch, throwsA(isA<RotateCaptchaCancelled>()));
    await tester.pump();
    session.logic.autoWatchEnabled = false;
    await session.logic.stopAutoWatch();
    await rejected; // Cancellation does not wait for the API response.
    final reads = session.view.reads;
    response.complete(http.Response('{"angle":180}', 200));
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.view.reads, reads);
    expect(session.drags, 0);
    expect(session.touches, 0);
    expect(session.notices, isEmpty);
    await finish(session, tester);
  });

  testWidgets('failed CAPTCHA stops nurture and further polling', (
    tester,
  ) async {
    final session = _Session(respond: () async => http.Response('{}', 401));
    attach(session);
    await session.logic.startAutoWatch();
    session.view.captcha = true;
    await tester.pump(const Duration(seconds: 1));
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.notices.single, contains('HTTP 401'));
    final reads = session.view.reads;
    session.view.image = 'AQIE';
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.view.reads, reads);
    expect(session.drags, 0);
    await finish(session, tester);
  });

  testWidgets('Android nurture checks Profile while waiting for a video', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final session = _Session();
    session.view.path = '/@fixture';
    attach(session);
    await session.logic.startAutoWatch();
    await tester.pump();
    session.view.captcha = true;
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.drags, 1);
    expect(session.logic.autoWatchEnabled, isTrue);
    await finish(session, tester);
  });

  for (final flow in ['idle', 'signup', 'login']) {
    testWidgets('does not inspect or solve CAPTCHA outside nurture: $flow', (
      tester,
    ) async {
      final session = _Session(watch: false);
      session.logic.autoSignupBusy = flow == 'signup';
      session.logic.autoLoginBusy = flow == 'login';
      attach(session);
      session.view.captcha = true;
      await session.logic.signupAccessibility.snapshot();
      await session.logic.signupAccessibility.tap(
        SignupViewport(const Rect.fromLTWH(0, 0, 400, 800)),
        const Offset(100, 200),
      );
      session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      await _pumpSolve(tester);
      expect(session.view.reads, 0);
      expect(session.requests, 0);
      expect(session.drags, 0);
      expect(session.notices, isEmpty);
      await finish(session, tester);
    });
  }

  testWidgets('enabling nurture starts monitoring after idle browsing', (
    tester,
  ) async {
    final session = _Session(watch: false);
    attach(session);
    session.view.captcha = true;
    await _pumpSolve(tester);
    expect(session.view.reads, 0);
    session.logic.autoWatchEnabled = true;
    await session.logic.startAutoWatch();
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.drags, 1);
    await finish(session, tester);
  });

  for (final manualPlan in <NurturePlan?>[
    null,
    const NurturePlan(NurtureMode.feed),
  ]) {
    testWidgets(
      'manual viewing never starts the CAPTCHA monitor: $manualPlan',
      (tester) async {
        final session = _Session(
          watch: false,
          native: true,
          manualPlan: manualPlan,
        );
        attach(session);
        session.view.captcha = true;
        await _pumpSolve(tester);
        session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
        await tester.pump();
        session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await _pumpSolve(tester);
        expect(session.view.reads, 0);
        expect(session.requests, 0);
        expect(session.drags, 0);
        await finish(session, tester);
      },
    );
  }

  for (final pause in ['background', 'covered']) {
    testWidgets(
      '$pause suspends CAPTCHA and returning resumes only active nurture',
      (tester) async {
        final response = Completer<http.Response>();
        final session = _Session(respond: () => response.future);
        attach(session);
        await session.logic.startAutoWatch();
        session.view.captcha = true;
        await tester.pump(const Duration(seconds: 1));
        expect(session.requests, 1);
        if (pause == 'background') {
          session.logic.didChangeAppLifecycleState(AppLifecycleState.paused);
        } else {
          session.logic.setTikTokScreenVisible(false);
        }
        await tester.pump();
        response.complete(http.Response('{"angle":180}', 200));
        await _pumpSolve(tester);
        expect(session.drags, 0);
        if (pause == 'background') {
          session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        } else {
          session.logic.setTikTokScreenVisible(true);
        }
        await _pumpSolve(tester);
        expect(session.requests, 2);
        expect(session.drags, 1);
        await finish(session, tester);
      },
    );
  }

  testWidgets('permission failure uses no API credits and stops nurture', (
    tester,
  ) async {
    final session = _Session()..permission = false;
    attach(session);
    await session.logic.startAutoWatch();
    session.view.captcha = true;
    await _pumpSolve(tester);
    expect(session.logic.autoWatchEnabled, isFalse);
    expect(session.requests, 0);
    expect(session.drags, 0);
    expect(session.notices.single, contains('Trợ năng'));
    session.permission = true;
    session.logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
    await _pumpSolve(tester);
    expect(session.requests, 0); // Permission alone must not restart nurture.
    session.logic.autoWatchEnabled = true;
    await session.logic.startAutoWatch();
    await _pumpSolve(tester);
    expect(session.requests, 1);
    expect(session.drags, 1);
    await finish(session, tester);
  });

  testWidgets('never solves outside TikTok even while nurture is enabled', (
    tester,
  ) async {
    final session = _Session();
    attach(session);
    session.view.host = 'example.com';
    session.view.captcha = true;
    await _pumpSolve(tester);
    expect(session.requests, 0);
    expect(session.view.reads, 0);
    await finish(session, tester);
  });

  testWidgets('closing TikTok during confirmation cancels remaining timers', (
    tester,
  ) async {
    final session = _Session();
    attach(session);
    session.view.captcha = true;
    await tester.pump(const Duration(seconds: 1));
    expect(session.drags, 1);
    await finish(session, tester);
    expect(session.notices, isEmpty);
  });
}
