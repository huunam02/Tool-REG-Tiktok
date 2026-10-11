import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'app_configuration.dart';

const _proxyChannel = MethodChannel('test_tiktok/webview_proxy');

/// Complete the native override before constructing or loading the WebView.
Future<void> configureWebViewProxy(WebViewProxy? proxy) async {
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
    final supported =
        await WebViewFeature.isFeatureSupported(WebViewFeature.PROXY_OVERRIDE);
    if (!supported) {
      if (proxy != null) {
        throw PlatformException(
          code: 'proxy_unsupported',
          message: 'WebView trên thiết bị này không hỗ trợ cấu hình proxy.',
        );
      }
      return;
    }
    final controller = ProxyController.instance();
    if (proxy == null) {
      await controller.clearProxyOverride();
    } else {
      await controller.setProxyOverride(
        settings: ProxySettings(proxyRules: [ProxyRule(url: '${proxy.uri}')]),
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
