import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/scripts/auto_login_script.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const accessibilityChannel = MethodChannel('x-slayer/accessibility_channel');
  const targetChannel = MethodChannel('test_tiktok/send_code_target');
  late List<MethodCall> gestures;
  late List<MethodCall> targets;
  late List<MethodCall> invalidations;
  bool gestureSucceeds = true;
  Future<Map<String, double>?> Function()? readTarget;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    gestures = [];
    targets = [];
    invalidations = [];
    gestureSucceeds = true;
    readTarget = () async => {'x': 123.5, 'y': 456.0};
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(accessibilityChannel, (call) async {
      if (call.method == 'dispatchGesture') {
        gestures.add(call);
        return gestureSucceeds;
      }
      return true;
    });
    messenger.setMockMethodCallHandler(targetChannel, (call) async {
      if (call.method == 'invalidateTarget') {
        invalidations.add(call);
        return true;
      }
      targets.add(call);
      return readTarget!();
    });
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(accessibilityChannel, null);
    messenger.setMockMethodCallHandler(targetChannel, null);
  });

  Future<(TikTokController, _EmailView)> prepare() async {
    final view = _EmailView();
    final logic = TikTokController(
      configuration: AppConfiguration(
        userAgent: 'test-agent',
        comments: [],
        signupEmail: '',
        signupPassword: '',
        loginUsername: 'person@example.com',
        loginPassword: 'password',
      ),
      useAccessibility: true,
    )..onInit();
    addTearDown(logic.onClose);
    await logic.onWebViewCreated(
      InAppWebViewController.fromPlatform(platform: view),
    );
    expect(await logic.ensureAccountAccessibility(), isTrue);
    logic.autoLoginBusy = true;
    logic.autoLoginAttempt = 4;
    return (logic, view);
  }

  testWidgets(
    'Email handler dispatches one gesture at the native WebView point',
    (tester) async {
      final (logic, view) = await prepare();
      final handler = view.handlers['FlutterLoginEmailVerification']!;
      expect(await handler([3]), isFalse);
      expect(targets, isEmpty);
      expect(await handler([4]), isTrue);
      expect(targets.single.arguments, {
        'id': 77,
        'attempt': 4,
        'context': 'login',
        'action': 'select-verification-email',
      });
      expect(gestures.single.method, 'dispatchGesture');
      expect(gestures.single.arguments, {
        'strokes': [
          {
            'path': [
              {'x': 123.5, 'y': 456.0},
            ],
            'startTime': 0,
            'duration': 140,
          },
        ],
      });
      expect(await logic.clickLoginEmailVerification([4]), isFalse);
      expect(gestures, hasLength(1));
      expect(targets, hasLength(1));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'OTP Next handler dispatches one native gesture for the OTP step',
    (tester) async {
      final (logic, view) = await prepare();
      final handler = view.handlers['FlutterLoginOtpContinue']!;
      expect(await handler([3]), isFalse);
      expect(targets, isEmpty);
      expect(await handler([4]), isTrue);
      expect(targets.single.arguments, {
        'id': 77,
        'attempt': 4,
        'context': 'login',
        'action': 'continue-otp',
      });
      expect(gestures.single.method, 'dispatchGesture');
      expect(gestures.single.arguments['strokes'][0]['duration'], 140);
      expect(await handler([4]), isFalse);
      expect(gestures, hasLength(1));
      expect(targets, hasLength(1));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'Email gesture is rejected on another origin or without a target',
    (tester) async {
      final (logic, view) = await prepare();
      view.url = WebUri('https://example.com/');
      expect(await logic.clickLoginEmailVerification([4]), isFalse);
      expect(targets, isEmpty);
      logic.autoLoginAttempt = 5;
      view.url = WebUri('https://www.tiktok.com/');
      readTarget = () async => null;
      expect(await logic.clickLoginEmailVerification([5]), isFalse);
      expect(targets, hasLength(1));
      expect(gestures, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'failed Email tap invalidates its cache without repeating the gesture',
    (tester) async {
      final (logic, _) = await prepare();
      gestureSucceeds = false;
      expect(await logic.clickLoginEmailVerification([4]), isFalse);
      expect(invalidations.single.arguments, {
        'id': 77,
        'context': 'login',
        'action': 'select-verification-email',
      });
      expect(await logic.clickLoginEmailVerification([4]), isFalse);
      expect(gestures, hasLength(1));
      expect(targets, hasLength(1));
      logic.autoLoginAttempt = 5;
      gestureSucceeds = true;
      expect(await logic.clickLoginEmailVerification([5]), isTrue);
      expect(gestures, hasLength(2));
      expect(targets, hasLength(2));
      expect(invalidations, hasLength(1));
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'cancelling login while reading Email coordinates prevents dispatch',
    (tester) async {
      final (logic, _) = await prepare();
      final point = Completer<Map<String, double>?>();
      readTarget = () => point.future;
      final tap = logic.clickLoginEmailVerification([4]);
      await tester.pump();
      expect(targets, hasLength(1));
      logic.cancelAutoLogin();
      point.complete({'x': 123.5, 'y': 456.0});
      expect(await tap, isFalse);
      expect(gestures, isEmpty);
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets(
    'login enables native Email selection with a five second preparation delay',
    (tester) async {
      final (logic, view) = await prepare();
      logic.autoLoginBusy = false;
      final login = logic.autoLogin();
      await tester.pump();
      await tester.pump(const Duration(seconds: 10));
      await tester.pump();
      await login;
      final source = view.sources.singleWhere(
        (source) => source.contains(autoLoginStepScript),
      );
      expect(source, contains('"useAccessibilityEmailVerification":true'));
      expect(source, contains('"emailVerificationDelayMs":5000'));
      expect(
        TikTokController.isFastAccountStep('waiting-email-verification'),
        isTrue,
      );
      expect(
        TikTokController.isFastAccountStep('requesting-email-verification'),
        isTrue,
      );
      logic.onClose();
      debugDefaultTargetPlatformOverride = null;
    },
  );
}

class _EmailView extends PlatformInAppWebViewController {
  _EmailView()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 77),
      );

  WebUri url = WebUri('https://www.tiktok.com/');
  final handlers = <String, JavaScriptHandlerCallback>{};
  final sources = <String>[];

  @override
  Future<WebUri?> getUrl() async => url;

  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    return source.contains(autoLoginStepScript) ? 'login-success' : true;
  }
}
