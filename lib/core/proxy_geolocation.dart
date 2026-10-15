import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_configuration.dart';
import 'webview_privacy.dart';
import 'webview_user_agent.dart';

class ProxyGeolocation {
  const ProxyGeolocation({required this.ip, required this.timeZoneId});

  final String ip;
  final String timeZoneId;

  factory ProxyGeolocation.fromJson(dynamic data) {
    final zone = data is Map && data['timezone'] is Map
        ? data['timezone']['id']
        : null;
    final ip = data is Map ? data['ip'] : null;
    if (data is! Map ||
        data['success'] != true ||
        ip is! String ||
        InternetAddress.tryParse(ip) == null ||
        zone is! String ||
        zone.length > 100 ||
        !RegExp(r'^[A-Za-z][A-Za-z0-9_+\-/]*$').hasMatch(zone)) {
      throw const FormatException('API không trả về IP và múi giờ hợp lệ.');
    }
    return ProxyGeolocation(ip: ip, timeZoneId: zone);
  }
}

/// Navigate through the already configured native WebView proxy, including
/// HTTPS proxy support and proxy authentication. Never retry without a proxy.
class ProxyGeolocationLookup {
  ProxyGeolocationLookup({this.timeout = const Duration(seconds: 12)});

  final Duration timeout;
  bool _cancelled = false;
  Completer<ProxyGeolocation>? _pending;

  void cancel() {
    _cancelled = true;
    final pending = _pending;
    if (pending != null && !pending.isCompleted) {
      pending.completeError(const FormatException('Đã hủy kiểm tra múi giờ.'));
    }
  }

  Future<ProxyGeolocation> lookup({
    required WebViewProxy proxy,
    required String userAgent,
  }) async {
    if (_cancelled) throw const FormatException('Đã hủy kiểm tra múi giờ.');
    final result = Completer<ProxyGeolocation>();
    var proxyAuthAttempts = 0;
    _pending = result;
    void fail(String message) {
      if (!result.isCompleted) result.completeError(FormatException(message));
    }

    final request = URLRequest(
      url: WebUri('https://ipwho.is/?fields=success,ip,timezone.id'),
      headers: const {'Cache-Control': 'no-cache'},
    );
    final view = HeadlessInAppWebView(
      initialUserScripts: UnmodifiableListView([
        hideGpuInfoUserScript(),
        disableWebRtcUserScript(),
      ]),
      initialSettings: InAppWebViewSettings(
        userAgent: userAgent,
        preferredContentMode: UserPreferredContentMode.DESKTOP,
        javaScriptEnabled: true,
        incognito: false,
        cacheEnabled: false,
      ),
      onWebViewCreated: (controller) async {
        try {
          await configureAndroidDesktopIdentity(
            controller,
            userAgent: userAgent,
          );
          if (_cancelled || result.isCompleted) return;
          await controller.loadUrl(urlRequest: request);
        } catch (_) {
          fail('Không thể khởi tạo WebView kiểm tra múi giờ.');
        }
      },
      onLoadStop: (controller, url) async {
        if (result.isCompleted || url?.scheme == 'about') return;
        if (url?.scheme != 'https' || url?.host != 'ipwho.is') {
          fail('API múi giờ chuyển hướng đến địa chỉ không hợp lệ.');
          return;
        }
        try {
          final body = await controller.evaluateJavascript(
            source: 'document.body.innerText',
          );
          final location = ProxyGeolocation.fromJson(
            body is String ? jsonDecode(body) : null,
          );
          if (!result.isCompleted) result.complete(location);
        } catch (_) {
          fail(
            'ipwho.is không trả về múi giờ hợp lệ. Hãy kiểm tra proxy hoặc thử lại.',
          );
        }
      },
      onReceivedHttpAuthRequest: (controller, challenge) async {
        if (challenge.protectionSpace.host != proxy.uri.host) return null;
        if (_cancelled ||
            result.isCompleted ||
            proxy.username.isEmpty ||
            ++proxyAuthAttempts > 2 ||
            (challenge is HttpAuthenticationChallenge &&
                challenge.previousFailureCount > 1)) {
          fail('Proxy từ chối xác thực khi kiểm tra múi giờ.');
          return HttpAuthResponse(action: HttpAuthResponseAction.CANCEL);
        }
        return HttpAuthResponse(
          username: proxy.username,
          password: proxy.password,
          action: HttpAuthResponseAction.PROCEED,
          permanentPersistence: false,
        );
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame != false) {
          fail('Không thể kết nối ipwho.is qua proxy.');
        }
      },
      onReceivedHttpError: (controller, request, response) {
        if (request.isForMainFrame != false &&
            (response.statusCode ?? 0) >= 400) {
          fail(
            response.statusCode == 429
                ? 'ipwho.is đã giới hạn lượt kiểm tra. Hãy thử lại sau.'
                : 'Không thể kiểm tra múi giờ qua proxy.',
          );
        }
      },
    );
    final timer = Timer(
      timeout,
      () => fail('Kiểm tra múi giờ qua proxy quá thời gian chờ.'),
    );
    var finished = false;
    final startup = view.run();
    unawaited(
      startup
          .then((_) async {
            if (finished) await view.dispose();
          })
          .catchError((Object _) {}),
    );
    try {
      await Future.any<void>([startup, result.future.then((_) {})]);
      return await result.future;
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException(
        'Không thể khởi tạo kiểm tra múi giờ qua proxy.',
      );
    } finally {
      finished = true;
      timer.cancel();
      _pending = null;
      await view.dispose();
    }
  }
}
