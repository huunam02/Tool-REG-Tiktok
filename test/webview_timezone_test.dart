import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/webview_timezone.dart';

class _Controller extends PlatformInAppWebViewController {
  _Controller()
    : super.implementation(
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  bool ready = true;
  final events = <String>[];
  @override
  void addJavaScriptHandler({
    required String handlerName,
    required JavaScriptHandlerCallback callback,
  }) {}
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async {
    if (source.contains('const zone =')) events.add('timezone');
    return ready;
  }

  @override
  Future<void> loadUrl({
    required URLRequest urlRequest,
    Uri? iosAllowingReadAccessTo,
    WebUri? allowingReadAccessTo,
  }) async {
    events.add('load');
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('timezone is installed at document start in every frame', () {
    final script = webViewTimeZoneUserScript('America/New_York');
    expect(script.injectionTime, UserScriptInjectionTime.AT_DOCUMENT_START);
    expect(script.forMainFrameOnly, isFalse);
    expect(script.source, contains('const zone = "America/New_York";'));
    expect(script.source, isNot(contains('__PROXY_TIME_ZONE__')));
  });

  test(
    'timezone values are JSON encoded rather than interpolated as JavaScript',
    () {
      expect(
        webViewTimeZoneScript('bad";call();//'),
        contains('const zone = "bad\\";call();//";'),
      );
    },
  );

  for (final ready in [true, false]) {
    test(
      'timezone preflight $ready controls first external navigation',
      () async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        final messenger =
            TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
        const channel = MethodChannel('test_tiktok/webview_identity');
        messenger.setMockMethodCallHandler(channel, (_) async => 'agent');
        final native = _Controller()..ready = ready;
        final logic = TikTokController(
          configuration: AppConfiguration(
            userAgent: 'agent',
            signupEmail: '',
            signupPassword: '',
            loginUsername: '',
            loginPassword: '',
            comments: [],
            webViewTimeZone: 'America/New_York',
          ),
        );
        logic.onInit();
        try {
          await logic.onWebViewCreated(
            InAppWebViewController.fromPlatform(platform: native),
          );
          expect(native.events, ready ? ['timezone', 'load'] : ['timezone']);
          expect(logic.browserIdentityReady, ready);
          expect(logic.pageFailure == null, ready);
        } finally {
          logic.onClose();
          debugDefaultTargetPlatformOverride = null;
          messenger.setMockMethodCallHandler(channel, null);
        }
      },
    );
  }
}
