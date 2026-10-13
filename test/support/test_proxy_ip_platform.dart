import 'dart:async';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class TestProxyIpPlatform extends InAppWebViewPlatform {
  final probes = <TestProxyIpView>[];
  Completer<void>? startupGate;

  @override
  PlatformHeadlessInAppWebView createPlatformHeadlessInAppWebView(
      PlatformHeadlessInAppWebViewCreationParams params) {
    final view = TestProxyIpView(params, startupGate: startupGate);
    probes.add(view);
    return view;
  }
}

class TestProxyIpView extends PlatformHeadlessInAppWebView {
  TestProxyIpView(super.params, {this.startupGate}) : super.implementation();

  final Completer<void>? startupGate;

  final controller = TestProxyIpController();
  bool running = false;
  bool disposed = false;

  InAppWebViewController get callbackController =>
      InAppWebViewController.fromPlatform(platform: controller);

  void loaded(String body, {WebUri? url}) {
    controller.body = body;
    params.onLoadStop!(
        callbackController, url ?? params.initialUrlRequest!.url);
  }

  void failed({int status = 503}) => params.onReceivedHttpError!(
      callbackController,
      WebResourceRequest(
          url: params.initialUrlRequest!.url!, isForMainFrame: true),
      WebResourceResponse(statusCode: status));

  @override
  Future<void> run() async {
    if (startupGate != null) await startupGate!.future;
    running = true;
  }

  @override
  Future<void> dispose() async {
    if (!running) return;
    running = false;
    disposed = true;
  }
}

class TestProxyIpController extends PlatformInAppWebViewController {
  TestProxyIpController()
      : super.implementation(
            const PlatformInAppWebViewControllerCreationParams(id: 1));

  String? body;
  final scripts = <String>[];

  @override
  Future<dynamic> evaluateJavascript(
      {required String source, ContentWorld? contentWorld}) async {
    scripts.add(source);
    return body;
  }
}
