import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_configuration.dart';

const _proxyChannel = MethodChannel('test_tiktok/webview_proxy');
Future<void>? _proxyQueue;
WebViewProxy? _configuredProxy;

Future<T> _serializeProxy<T>(Future<T> Function() action) async {
  final previous = _proxyQueue;
  final finished = Completer<void>();
  _proxyQueue = finished.future;
  if (previous != null) await previous;
  try {
    return await action();
  } finally {
    if (identical(_proxyQueue, finished.future)) _proxyQueue = null;
    finished.complete();
  }
}

/// Complete the native override before constructing or loading the WebView.
Future<void> configureWebViewProxy(WebViewProxy? proxy) =>
    _serializeProxy(() => _applyWebViewProxy(proxy));

/// Imported proxies are probed sequentially and never become the selection.
/// Queue normal configuration changes until the original override is restored.
Future<T> withTemporaryWebViewProxy<T>(
  WebViewProxy proxy,
  Future<T> Function() action, {
  bool Function()? isCancelled,
}) => _serializeProxy(() async {
  if (isCancelled?.call() == true) {
    throw const FormatException('Đã hủy kiểm tra proxy.');
  }
  final original = _configuredProxy;
  try {
    await _applyWebViewProxy(proxy);
    return await action();
  } finally {
    await _applyWebViewProxy(original);
  }
});

Future<void> _applyWebViewProxy(WebViewProxy? proxy) async {
  await _configureNativeProxy(proxy);
  _configuredProxy = proxy;
}

Future<void> _configureNativeProxy(WebViewProxy? proxy) async {
  if (defaultTargetPlatform == TargetPlatform.iOS && !kIsWeb) {
    await _proxyChannel.invokeMethod<void>('configure', {
      'host': proxy?.uri.host,
      'port': proxy?.uri.port,
      'scheme': proxy?.uri.scheme,
      'username': proxy?.username,
      'password': proxy?.password,
    });
    return;
  }
  if (defaultTargetPlatform == TargetPlatform.android && !kIsWeb) {
    final supported = await WebViewFeature.isFeatureSupported(
      WebViewFeature.PROXY_OVERRIDE,
    );
    if (!supported) {
      if (proxy != null) {
        throw PlatformException(
          code: 'proxy_unsupported',
          message: 'WebView trên thiết bị này không hỗ trợ cấu hình proxy.',
        );
      }
      return;
    }
    // A late JavaScript fallback could expose ICE candidates before the guard.
    if (proxy != null &&
        !await WebViewFeature.isFeatureSupported(
          WebViewFeature.DOCUMENT_START_SCRIPT,
        )) {
      throw PlatformException(
        code: 'proxy_unsupported',
        message:
            'Không thể chặn WebRTC trước khi tải trang. '
            'Hãy cập nhật Android System WebView rồi thử lại.',
      );
    }
    final controller = ProxyController.instance();
    if (proxy == null) {
      await controller.clearProxyOverride();
    } else {
      await controller.setProxyOverride(
        settings: ProxySettings(
          proxyRules: [ProxyRule(url: '${proxy.uri}')],
          // Do not let localhost/link-local requests bypass the proxy.
          removeImplicitRules: true,
        ),
      );
    }
    return;
  }
  if (proxy != null) {
    throw PlatformException(
      code: 'proxy_unsupported',
      message: 'Cấu hình proxy hiện hỗ trợ Android và iOS 17 trở lên.',
    );
  }
}
