import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:test_tiktok/core/webview_failure.dart';

void main() {
  test('native iOS connection failures produce readable proxy notices', () {
    for (final type in [
      WebResourceErrorType.CANNOT_CONNECT_TO_HOST,
      WebResourceErrorType.TIMEOUT,
      WebResourceErrorType.NETWORK_CONNECTION_LOST,
    ]) {
      final failure = WebViewFailure.network(
          WebResourceError(type: type, description: 'A native network error'),
          usingProxy: true);
      expect(failure.title, 'Lỗi kết nối proxy');
      expect(failure.message, contains('proxy'));
      expect(failure.isConnectionFailure, isTrue);
    }
  });

  test('proxy authentication failure is distinguished from unknown errors', () {
    final failure = WebViewFailure.network(
        WebResourceError(
            type: WebResourceErrorType.PROXY_AUTHENTICATION,
            description: 'Authentication failed'),
        usingProxy: true);
    expect(failure, WebViewFailure.proxyAuth);
    final unknown = WebViewFailure.network(
        WebResourceError(
            type: WebResourceErrorType.UNKNOWN,
            description: 'Internal details with secret-password'),
        usingProxy: true);
    expect(unknown.message, isNot(contains('secret-password')));
    expect(unknown.isConnectionFailure, isFalse);
  });
}
