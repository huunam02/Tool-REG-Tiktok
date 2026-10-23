import 'dart:async';

import 'app_configuration.dart';
import 'gecko_browser.dart';

Future<void>? _proxyQueue;
WebViewProxy? _configuredProxy;
String _configuredProfileId = 'default';
String _configuredLabel = '';

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

/// Switches the app-scoped Android VPN before constructing a GeckoSession.
/// [label] names the configuration in the VPN notification.
Future<void> configureWebViewProxy(
  WebViewProxy? proxy, {
  String profileId = 'default',
  String label = '',
}) => _serializeProxy(() => _applyProxy(proxy, profileId, label));

Future<T> withTemporaryWebViewProxy<T>(
  WebViewProxy proxy,
  Future<T> Function() action, {
  bool Function()? isCancelled,
}) => _serializeProxy(() async {
  if (isCancelled?.call() == true) {
    throw const FormatException('Đã hủy kiểm tra proxy.');
  }
  final original = _configuredProxy;
  final originalId = _configuredProfileId;
  final originalLabel = _configuredLabel;
  try {
    await _applyProxy(
      proxy,
      'temporary-${DateTime.now().microsecondsSinceEpoch}',
      'Kiểm tra proxy',
    );
    return await action();
  } finally {
    await _applyProxy(original, originalId, originalLabel);
  }
});

Future<void> _applyProxy(
  WebViewProxy? proxy,
  String profileId,
  String label,
) async {
  if (proxy == null) {
    await ProfileVpn.stop();
  } else {
    if (!const {
      'socks5',
      'socks5h',
      'http',
      'https',
    }.contains(proxy.uri.scheme)) {
      throw const FormatException('Proxy phải dùng HTTP, HTTPS hoặc SOCKS5.');
    }
    await ProfileVpn.start(
      profileId: profileId,
      proxy: proxy.uri,
      username: proxy.username,
      password: proxy.password,
      label: label.isEmpty ? proxy.uri.host : '$label · ${proxy.uri.host}',
    );
  }
  _configuredProxy = proxy;
  _configuredProfileId = profileId;
  _configuredLabel = label;
}
