import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/app_configuration.dart';
import 'package:test_tiktok/screen/tiktok_page.dart';

class _Platform extends InAppWebViewPlatform {
  @override
  PlatformInAppWebViewWidget createPlatformInAppWebViewWidget(
          PlatformInAppWebViewWidgetCreationParams params) =>
      _WebView(params);
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
            const PlatformInAppWebViewControllerCreationParams(id: 0));

  final handlers = <String, JavaScriptHandlerCallback>{};
  final sources = <String>[];
  int reloads = 0;

  @override
  void addJavaScriptHandler(
      {required String handlerName,
      required JavaScriptHandlerCallback callback}) {
    handlers[handlerName] = callback;
  }

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    sources.add(source);
    return true;
  }

  @override
  Future<WebUri?> getUrl() async => WebUri(tiktokHomeUrl);

  @override
  Future<void> reload() async => reloads++;
}

void main() {
  setUp(() {
    final previousPlatform = InAppWebViewPlatform.instance;
    InAppWebViewPlatform.instance = _Platform();
    addTearDown(() {
      debugDefaultTargetPlatformOverride = null;
      if (previousPlatform != null) {
        InAppWebViewPlatform.instance = previousPlatform;
      }
    });
  });

  Future<PlatformInAppWebViewWidgetCreationParams> mount(WidgetTester tester,
      {bool usingProxy = true, String username = 'test-user'}) async {
    await tester.pumpWidget(MaterialApp(
        home: TikTokPage(
            configuration: AppConfiguration(
      userAgent: 'test-agent',
      comments: [],
      signupEmail: '',
      signupPassword: '',
      loginUsername: '',
      loginPassword: '',
      proxy: usingProxy
          ? WebViewProxy.parse('proxy.example.com:8080',
              username: username, password: 'test-password')
          : null,
    ))));
    return tester
        .widget<InAppWebView>(find.byType(InAppWebView))
        .platform
        .params;
  }

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform sends proxy credentials on the first challenge only',
        (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      final params = await mount(tester);
      final controller =
          InAppWebViewController.fromPlatform(platform: _Controller());
      final firstCount = platform == TargetPlatform.android ? 1 : 0;
      Future<HttpAuthResponse?> challenge(
              String host, int failureCount) async =>
          params.onReceivedHttpAuthRequest!(
            controller,
            HttpAuthenticationChallenge(
              protectionSpace: URLProtectionSpace(host: host, port: 8080),
              previousFailureCount: failureCount,
            ),
          );

      // Never send the proxy's credentials to a destination website.
      expect(await challenge('www.tiktok.com', firstCount), isNull);
      final response = await challenge('proxy.example.com', firstCount);
      expect(response?.action, HttpAuthResponseAction.PROCEED);
      expect(response?.username, 'test-user');
      expect(response?.password, 'test-password');
      expect(response?.permanentPersistence, isFalse);
      expect((await challenge('proxy.example.com', firstCount + 1))?.action,
          HttpAuthResponseAction.CANCEL);
      await tester.pump();
      expect(find.text('Proxy từ chối xác thực'), findsOneWidget);
      expect(find.byKey(const Key('proxyWarningBanner')), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('subresource failures do not replace a successfully loaded page',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 700));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final params = await mount(tester);
    final controller =
        InAppWebViewController.fromPlatform(platform: _Controller());
    final error = WebResourceError(
        type: WebResourceErrorType.UNKNOWN,
        description: 'net::ERR_TUNNEL_CONNECTION_FAILED');
    params.onReceivedError!(
        controller,
        WebResourceRequest(
            url: WebUri('https://api.ipify.org'), isForMainFrame: false),
        error);
    await tester.pump();
    expect(find.byKey(const Key('webViewFailure')), findsNothing);
    expect(find.byKey(const Key('proxyWarningBanner')), findsOneWidget);
    expect(tester.takeException(), isNull);

    params.onReceivedError!(
        controller,
        WebResourceRequest(url: WebUri(tiktokHomeUrl), isForMainFrame: true),
        error);
    await tester.pump();
    expect(find.byKey(const Key('webViewFailure')), findsOneWidget);
    expect(find.text('Lỗi kết nối proxy'), findsOneWidget);
    expect(find.text('ERR_TUNNEL_CONNECTION_FAILED'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('407 notifies about proxy authentication and retry reloads',
      (tester) async {
    final params = await mount(tester);
    final platformController = _Controller();
    final controller =
        InAppWebViewController.fromPlatform(platform: platformController);
    params.onWebViewCreated!(controller);
    params.onReceivedHttpError!(
        controller,
        WebResourceRequest(url: WebUri(tiktokHomeUrl), isForMainFrame: true),
        WebResourceResponse(statusCode: 407));
    await tester.pump();
    expect(find.text('Proxy từ chối xác thực'), findsOneWidget);
    expect(find.text('HTTP 407'), findsOneWidget);
    await tester.tap(find.byKey(const Key('retryWebViewFailure')));
    expect(platformController.reloads, 1);
    params.onLoadStart!(controller, WebUri(tiktokHomeUrl));
    await tester.pump();
    expect(find.byKey(const Key('webViewFailure')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('missing proxy credentials are reported before cancelling auth',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final params = await mount(tester, username: '');
    final response = await params.onReceivedHttpAuthRequest!(
        InAppWebViewController.fromPlatform(platform: _Controller()),
        HttpAuthenticationChallenge(
            protectionSpace: URLProtectionSpace(host: 'proxy.example.com'),
            previousFailureCount: 1));
    await tester.pump();
    expect(response?.action, HttpAuthResponseAction.CANCEL);
    expect(find.text('Proxy yêu cầu xác thực'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'failed IP check warns, retry recovers and stale results are ignored',
      (tester) async {
    final params = await mount(tester);
    final platformController = _Controller();
    final controller =
        InAppWebViewController.fromPlatform(platform: platformController);
    params.onWebViewCreated!(controller);
    params.onLoadStart!(controller, WebUri(tiktokHomeUrl));
    params.onLoadStop!(controller, WebUri(tiktokHomeUrl));
    await tester.pumpAndSettle();
    final receiveIp = platformController.handlers['FlutterProxyIp']!;
    await receiveIp([1, 'Không xác định']);
    await tester.pump();
    expect(find.text('Chưa xác minh được IP qua proxy'), findsOneWidget);
    expect(find.byKey(const Key('webViewFailure')), findsNothing);
    await tester.tap(find.byKey(const Key('retryProxyWarning')));
    await tester.pump();
    await receiveIp([1, '203.0.113.7']);
    await tester.pump();
    expect(find.text('IP: 203.0.113.7'), findsOneWidget);
    expect(find.byKey(const Key('proxyWarningBanner')), findsNothing);

    params.onLoadStart!(controller, WebUri(tiktokHomeUrl));
    await receiveIp([1, 'Không xác định']);
    await tester.pump();
    expect(find.text('IP: 203.0.113.7'), findsNothing);
    expect(find.byKey(const Key('proxyWarningBanner')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
      'direct connections do not show proxy warnings when IP check fails',
      (tester) async {
    final params = await mount(tester, usingProxy: false);
    final platformController = _Controller();
    params.onWebViewCreated!(
        InAppWebViewController.fromPlatform(platform: platformController));
    await platformController.handlers['FlutterProxyIp']!([0, 'Không xác định']);
    await tester.pump();
    expect(find.byKey(const Key('proxyWarningBanner')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}
