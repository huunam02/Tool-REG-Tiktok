import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'webview_locale.dart';

/// Navigate a separate WebView so TikTok's CSP/CORS cannot block the IP check.
/// Both views use Android's global override or iOS's default data store proxy.
class WebViewProxyIpChecker {
  WebViewProxyIpChecker({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;
  bool _cancelled = false;
  Completer<String?>? _pending;

  void cancel() {
    _cancelled = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) pending.complete(null);
  }

  Future<String?> check({
    required String userAgent,
    required Future<HttpAuthResponse?> Function(
            InAppWebViewController, URLAuthenticationChallenge)
        onAuth,
  }) async {
    for (final host in ['api.ipify.org', 'api64.ipify.org']) {
      if (_cancelled) return null;
      final result = Completer<String?>();
      _pending = result;
      var authFailed = false;
      void finish(String? ip) {
        if (!result.isCompleted) result.complete(ip);
      }

      final view = HeadlessInAppWebView(
        initialUrlRequest: URLRequest(
          url: WebUri(Uri.https(host, '/', {
            'format': 'json',
            '_': DateTime.now().microsecondsSinceEpoch.toString(),
          }).toString()),
          headers: const {
            ...englishWebViewHeaders,
            'Cache-Control': 'no-cache',
          },
        ),
        initialSettings: InAppWebViewSettings(
          userAgent: userAgent,
          javaScriptEnabled: true,
          // Non-persistent stores on iOS would lose the configured proxy.
          incognito: false,
          cacheEnabled: true,
        ),
        onLoadStop: (controller, url) async {
          if (result.isCompleted) return;
          if (url?.scheme != 'https' || url?.host != host) {
            finish(null);
            return;
          }
          try {
            final body = await controller.evaluateJavascript(
                source: 'document.body.innerText');
            final data = body is String ? jsonDecode(body) : null;
            final ip = data is Map ? data['ip'] : null;
            finish(ip is String && InternetAddress.tryParse(ip) != null
                ? ip
                : null);
          } catch (_) {
            finish(null);
          }
        },
        onReceivedError: (controller, request, error) {
          if (request.isForMainFrame != false) finish(null);
        },
        onReceivedHttpError: (controller, request, response) {
          if (request.isForMainFrame != false &&
              (response.statusCode ?? 0) >= 400) {
            authFailed = response.statusCode == 407;
            finish(null);
          }
        },
        onReceivedHttpAuthRequest: (controller, challenge) async {
          if (_cancelled || result.isCompleted) {
            return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
          }
          final response = await onAuth(controller, challenge);
          if (response?.action == HttpAuthResponseAction.CANCEL) {
            authFailed = true;
            finish(null);
          }
          return response;
        },
      );
      final timer = Timer(timeout, () => finish(null));
      var finished = false;
      final startup = view.run();
      // A native view can finish starting after cancellation or timeout.
      // Release it then as well, because dispose() before run() ends is a no-op.
      unawaited(startup.then((_) async {
        if (finished) await view.dispose();
      }).catchError((Object _) {}));
      try {
        await Future.any<void>([startup, result.future.then((_) {})]);
        final ip = await result.future;
        if (_cancelled) return null;
        if (ip != null || authFailed) return ip;
      } catch (_) {
        // Try the second endpoint using the same WebView proxy configuration.
      } finally {
        finished = true;
        timer.cancel();
        finish(null);
        _pending = null;
        await view.dispose();
      }
    }
    return null;
  }
}
