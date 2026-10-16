import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/webview_privacy.dart';
import 'package:test_tiktok/core/nurture_data.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';
import 'support/memory_nurture_store.dart';

class _Platform extends InAppWebViewPlatform {
  PlatformInAppWebViewWidgetCreationParams? webViewParams;

  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) {
    webViewParams = params;
    return _View(params);
  }
}

class _View extends PlatformInAppWebViewWidget {
  _View(super.params) : super.implementation();
  @override
  Widget build(BuildContext context) => const SizedBox.expand();
  @override
  T controllerFromPlatform<T>(PlatformInAppWebViewController controller) =>
      throw UnimplementedError();
  @override
  void dispose() {}
}

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 1),
      );
  final sources = <String>[];
  final loads = <URLRequest>[];
  final handlers = <String>[];
  final callbacks = <String, JavaScriptHandlerCallback>{};
  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async => loads.add(urlRequest);
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {
    handlers.add(handlerName);
    callbacks[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    sources.add(source);
    return true;
  }
}

class _RecordingController extends TikTokController {
  _RecordingController(TikTokLaunchAction action)
    : super(
        configuration: AppConfiguration.defaults('Chrome/155.0.0.0'),
        launchAction: action,
      );
  int logins = 0;
  int signups = 0;
  int ipChecks = 0;
  @override
  Future<void> autoLogin() async => logins++;
  @override
  Future<void> autoSignup() async => signups++;
  @override
  Future<void> checkProxyIp() async => ipChecks++;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Platform platform;
  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    platform = _Platform();
    InAppWebViewPlatform.instance = platform;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  test(
    'manual topic session navigates once and persists only passive snapshots',
    () async {
      const channel = MethodChannel('test_tiktok/webview_identity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (_) async => 'Chrome/134.0.0.0');
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final repository = MemoryNurtureRepository(() async => []);
      const plan = NurturePlan(NurtureMode.search, 'Du lịch & cà phê');
      final logic = TikTokController(
        configuration: AppConfiguration(
          userAgent: 'agent',
          signupEmail: 'person@example.com',
          signupPassword: 'password',
          loginUsername: 'person@example.com',
          loginPassword: 'password',
          comments: const ['Existing comment'],
        ),
        launchAction: TikTokLaunchAction.signup,
        manualViewingPlan: plan,
        nurtureRepository: repository,
      )..onInit();
      final native = _Controller();
      final controller = InAppWebViewController.fromPlatform(platform: native);
      await logic.onWebViewCreated(controller);
      final url = WebUri(plan.initialUrl);
      logic.onLoadStart(controller, url);
      await logic.onLoadStop(controller, url);
      await logic.onLoadStop(controller, url);
      await logic.autoSignup();
      await logic.toggleAutoWatch();
      expect(logic.useNativeWebView, isTrue);
      expect(native.loads.single.url.toString(), plan.initialUrl);
      expect(native.handlers, ['FlutterManualViewingStats']);
      expect(
        native.sources.where(
          (source) => source.contains('__manualViewingConfig'),
        ),
        hasLength(1),
      );
      expect(logic.autoWatchEnabled, isFalse);
      final id = repository.sessions.keys.single;
      await native.callbacks['FlutterManualViewingStats']!([
        {
          'session': id,
          'segment': '1',
          'sequence': 1,
          'watch_ms': 2500,
          'videos': 1,
          'full_videos': 0,
          'skipped_videos': 1,
          'comments': 0,
        },
      ]);
      logic.didChangeAppLifecycleState(AppLifecycleState.paused);
      await Future<void>.delayed(Duration.zero);
      expect(repository.phases[id], 'paused');
      await logic.closeManualViewing();
      expect(repository.phases[id], 'stopped');
      expect(repository.totals[id]!.watchMilliseconds, 2500);
      expect(repository.sessions[id]!.plan, same(plan));
      expect(native.loads, hasLength(1));
      logic.onClose();
    },
  );

  testWidgets(
    'manual viewing status is visible and automatic controls are absent',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: TikTokPage(
            configuration: AppConfiguration.defaults('agent'),
            manualViewingPlan: const NurturePlan(NurtureMode.search, 'Cà phê'),
          ),
        ),
      );
      expect(find.byKey(const Key('manualViewingStatus')), findsOneWidget);
      expect(
        find.text('Nuôi search keyword · Cà phê · xem thủ công'),
        findsOneWidget,
      );
      expect(find.byKey(const Key('autoWatch')), findsNothing);
      expect(find.byKey(const Key('nativeWebView')), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    },
  );

  testWidgets('native mode retains provider identity and Local IP protection', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: TikTokPage(
          configuration: AppConfiguration.defaults('Chrome/151.0.0.0'),
          useNativeWebView: true,
        ),
      ),
    );
    final view = platform.webViewParams!;
    expect(view.initialSettings!.userAgent, isNull);
    expect(
      view.initialSettings!.preferredContentMode,
      UserPreferredContentMode.DESKTOP,
    );
    expect(view.initialUrlRequest, isNull);
    expect(view.initialUserScripts!.map((s) => s.source), [
      disableWebRtcScript,
    ]);
    expect(find.byKey(const Key('autoWatch')), findsNothing);
    expect(find.text('TikTok · Tương thích'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  test(
    'engine mode uses the installed version without account automation',
    () async {
      var identityCalls = 0;
      const channel = MethodChannel('test_tiktok/webview_identity');
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
            identityCalls++;
            expect(call.method, 'configureEngine');
            expect(call.arguments.keys, ['id']);
            return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
                '(KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
          });
      addTearDown(
        () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, null),
      );
      final logic = TikTokController(
        configuration: AppConfiguration.defaults('Chrome/151.0.0.0'),
        launchAction: TikTokLaunchAction.signup,
        useNativeWebView: true,
      )..onInit();
      final controller = _Controller();
      await logic.onWebViewCreated(
        InAppWebViewController.fromPlatform(platform: controller),
      );
      await logic.handlePageLoadComplete(WebUri(tiktokHomeUrl));
      await logic.runInitialAction();
      await logic.autoSignup();
      await logic.autoLogin();
      await logic.toggleAutoWatch();
      logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
      logic.onClose();
      expect(identityCalls, 1);
      expect(controller.loads.single.url.toString(), tiktokHomeUrl);
      expect(controller.loads.single.headers, isNull);
      expect(controller.sources, isEmpty);
      expect(controller.handlers, isEmpty);
      expect(logic.browserIdentityReady, isTrue);
    },
  );
  for (final action in TikTokLaunchAction.values) {
    testWidgets(
      '$action defaults to the engine profile and retains automation UI',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TikTokPage(
              configuration: AppConfiguration.defaults('Chrome/155.0.0.0'),
              launchAction: action,
            ),
          ),
        );
        final view = platform.webViewParams!;
        expect(view.initialSettings!.userAgent, isNull);
        expect(view.initialUrlRequest, isNull);
        expect(
          view.initialUserScripts!.any(
            (script) => script.source == pixelGpuInfoScript,
          ),
          isFalse,
        );
        expect(
          view.initialUserScripts!.any(
            (script) => script.source == disableWebRtcScript,
          ),
          isTrue,
        );
        expect(find.byKey(const Key('autoWatch')), findsOneWidget);
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );

    testWidgets(
      '$action waits for engine configuration and starts once across reload/resume',
      (tester) async {
        final gate = Completer<String>();
        const agent =
            'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/134.0.0.0 Safari/537.36';
        const channel = MethodChannel('test_tiktok/webview_identity');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
              if (call.method == 'configureSignupViewport') {
                expect(action, TikTokLaunchAction.signup);
                return true;
              }
              expect(call.method, 'configureEngine');
              expect(call.arguments.keys, action == TikTokLaunchAction.signup
                  ? ['id', 'fixedSignupViewport'] : ['id']);
              return gate.future;
            });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance
              .defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final logic = _RecordingController(action)..onInit();
        final controller = _Controller();
        final wrapped = InAppWebViewController.fromPlatform(
          platform: controller,
        );
        final created = logic.onWebViewCreated(wrapped);
        await tester.pump();
        expect(controller.loads, isEmpty);
        expect(logic.browserIdentityReady, isFalse);
        expect(logic.logins + logic.signups, 0);
        gate.complete(agent);
        await created;
        expect(logic.effectiveUserAgent, agent);
        expect(controller.loads.single.url.toString(), tiktokHomeUrl);
        if (action == TikTokLaunchAction.signup) {
          expect(controller.handlers, isNot(contains('FlutterSignupSendCode')));
          expect(controller.handlers, isNot(contains('FlutterSignupPaste')));
        } else {
          expect(controller.handlers,
            containsAll(['FlutterLoginSendCode', 'FlutterSignupSendCode']));
        }
        await logic.handlePageLoadComplete(WebUri(tiktokHomeUrl));
        logic.onLoadStart(wrapped, WebUri(tiktokHomeUrl));
        await logic.handlePageLoadComplete(WebUri(tiktokHomeUrl));
        logic.didChangeAppLifecycleState(AppLifecycleState.resumed);
        await tester.pump();
        expect(logic.logins, action == TikTokLaunchAction.login ? 1 : 0);
        expect(logic.signups, action == TikTokLaunchAction.signup ? 1 : 0);
        logic.onClose();
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }

  for (final startWithIp in [false, true]) {
    testWidgets(
      'settings check IP=$startWithIp uses the same engine identity',
      (tester) async {
        await tester.pumpWidget(
          MaterialApp(
            home: TikTokPage(
              configuration: AppConfiguration.defaults('Chrome/155.0.0.0'),
              startWithBrowserCheck: !startWithIp,
              startWithIpCheck: startWithIp,
            ),
          ),
        );
        final view = platform.webViewParams!;
        expect(view.initialSettings!.userAgent, isNull);
        expect(
          view.initialSettings!.preferredContentMode,
          UserPreferredContentMode.DESKTOP,
        );
        expect(
          view.initialUserScripts!.any(
            (script) => script.source == pixelGpuInfoScript,
          ),
          isFalse,
        );
        await tester.pumpWidget(const SizedBox.shrink());
        debugDefaultTargetPlatformOverride = null;
      },
    );
  }
}
