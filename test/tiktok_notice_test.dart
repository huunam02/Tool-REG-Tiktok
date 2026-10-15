import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get/get.dart';
import 'package:test_tiktok/controller/tiktok_controller.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/core/tiktok_account_failure.dart';
import 'package:test_tiktok/core/webview_failure.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';

class _Platform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
    PlatformInAppWebViewWidgetCreationParams params,
  ) => _WebView(params);
}

class _WebView extends PlatformInAppWebViewWidget {
  _WebView(super.params) : super.implementation();

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
        const PlatformInAppWebViewControllerCreationParams(id: 0),
      );
  int reloads = 0;
  @override
  Future<dynamic> evaluateJavascript({
    required String source,
    ContentWorld? contentWorld,
  }) async => true;
  @override
  Future<void> reload() async => reloads++;
}

void main() {
  setUp(() {
    final previous = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _Platform();
    addTearDown(() {
      if (previous != null) InAppWebViewPlatform.instance = previous;
    });
  });

  Future<TikTokController> mount(
    WidgetTester tester, {
    bool routed = false,
  }) async {
    final page = TikTokPage(
      configuration: AppConfiguration(
        userAgent: 'test-agent',
        comments: [],
        signupEmail: '',
        signupPassword: '',
        loginUsername: '',
        loginPassword: '',
        proxy: WebViewProxy.parse('proxy.example.com:8080'),
      ),
    );
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navigator,
        home: routed ? const Scaffold(body: Text('Cấu hình gốc')) : page,
      ),
    );
    if (routed) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => page),
      );
      await tester.pumpAndSettle();
    }
    return tester
        .state<GetBuilderState<TikTokController>>(
          find.byType(GetBuilder<TikTokController>),
        )
        .controller!;
  }

  testWidgets('account toast and auto controls never resize the WebView', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(400, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final logic = await mount(tester);
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: _Controller(),
    );
    final webView = find.byType(InAppWebView);
    final originalBounds = tester.getRect(webView);
    logic.mutate(() => logic.autoSignupBusy = true);
    await tester.pump();
    expect(find.text('Dừng'), findsOneWidget);
    expect(tester.getRect(webView), originalBounds);

    logic.showAccountFailure(TikTokAccountFailure.rateLimited);
    await tester.pumpAndSettle();
    expect(logic.autoSignupBusy, isFalse);
    expect(find.byKey(const Key('accountFailureBanner')), findsNothing);
    expect(
      find.textContaining('TikTok đang giới hạn số lần thử'),
      findsOneWidget,
    );
    expect(
      tester.widget<SnackBar>(find.byType(SnackBar)).behavior,
      SnackBarBehavior.floating,
    );
    expect(tester.getRect(webView), originalBounds);
    expect(
      tester.getBottomRight(find.byType(SnackBar)).dy,
      greaterThan(originalBounds.center.dy),
    );
    await tester.pump(const Duration(seconds: 7));
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsNothing);
    expect(tester.getRect(webView), originalBounds);
    expect(logic.accountFailure, TikTokAccountFailure.rateLimited);
  });

  testWidgets('loading, long status, IP and keyboard keep the WebView bounds', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    addTearDown(tester.view.resetViewInsets);
    final logic = await mount(tester);
    final webView = find.byType(InAppWebView);
    final bounds = tester.getRect(webView);

    for (final progress in [40, 100, 0, 100]) {
      logic.mutate(() => logic.loadingProgress = progress);
      await tester.pump();
      expect(tester.getRect(webView), bounds);
    }
    logic.mutate(() {
      logic.detectedIp = '203.0.113.10';
      logic.autoSignupBusy = true;
      logic.signupStatus = List.filled(
        20,
        'Đang chờ mạng tải biểu mẫu…',
      ).join(' ');
    });
    await tester.pump();
    expect(tester.getRect(webView), bounds);
    final controls = tester.getRect(
      find.byKey(const Key('accountAutoControls')),
    );
    expect(controls.width, lessThanOrEqualTo(280));
    expect(controls.height, lessThan(100));

    tester.view.viewInsets = const FakeViewPadding(bottom: 300);
    await tester.pump();
    expect(tester.getRect(webView), bounds);
    logic.mutate(() {
      logic.autoSignupBusy = false;
      logic.autoLoginBusy = true;
    });
    await tester.pump();
    expect(tester.getRect(webView), bounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'page failure stays in a small overlay and preserves the WebView',
    (tester) async {
      await tester.binding.setSurfaceSize(const Size(320, 700));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      final logic = await mount(tester);
      final bounds = tester.getRect(find.byType(InAppWebView));
      logic.showPageFailure(WebViewFailure.proxyAuth);
      await tester.pumpAndSettle();
      final error = tester.getRect(find.byKey(const Key('webViewFailure')));
      expect(error.width, lessThanOrEqualTo(340));
      expect(error.height, lessThanOrEqualTo(220));
      expect(error.height, lessThan(bounds.height / 2));
      expect(tester.getRect(find.byType(InAppWebView)), bounds);
      expect(find.byKey(const Key('retryWebViewFailure')), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('proxy toast replaces previous notice and retry still reloads', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final logic = await mount(tester);
    final controller = _Controller();
    logic.webViewController = InAppWebViewController.fromPlatform(
      platform: controller,
    );
    final bounds = tester.getRect(find.byType(InAppWebView));
    logic.showProxyWarning(WebViewFailure.proxyAuth);
    logic.showProxyWarning(WebViewFailure.missingProxyAuth);
    await tester.pumpAndSettle();
    expect(find.byType(SnackBar), findsOneWidget);
    expect(find.textContaining('Proxy từ chối xác thực'), findsNothing);
    expect(find.textContaining('Proxy yêu cầu xác thực'), findsOneWidget);
    expect(find.byKey(const Key('proxyWarningBanner')), findsNothing);
    expect(tester.getRect(find.byType(InAppWebView)), bounds);
    await tester.tap(find.widgetWithText(SnackBarAction, 'Thử lại'));
    await tester.pumpAndSettle();
    expect(controller.reloads, 1);
    expect(tester.getRect(find.byType(InAppWebView)), bounds);
    expect(tester.takeException(), isNull);
  });

  testWidgets('account toast can return to configuration', (tester) async {
    final logic = await mount(tester, routed: true);
    logic.showAccountFailure(TikTokAccountFailure.rateLimited);
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(SnackBarAction, 'Cấu hình'));
    await tester.pumpAndSettle();
    expect(find.text('Cấu hình gốc'), findsOneWidget);
    expect(find.byType(InAppWebView), findsNothing);
  });
}
