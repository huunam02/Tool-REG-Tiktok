import 'package:flutter_inappwebview/flutter_inappwebview.dart';

class WebViewFailure {
  const WebViewFailure(this.title, this.message,
      {this.code, this.isConnectionFailure = false});

  final String title;
  final String message;
  final String? code;
  final bool isConnectionFailure;

  static const proxyAuth = WebViewFailure('Proxy từ chối xác thực',
      'Kiểm tra tài khoản, mật khẩu hoặc quyền truy cập của proxy rồi thử lại.',
      code: 'HTTP 407', isConnectionFailure: true);

  static const missingProxyAuth = WebViewFailure('Proxy yêu cầu xác thực',
      'Bổ sung tài khoản và mật khẩu proxy trong Quản lý cấu hình rồi mở lại TikTok.',
      code: 'HTTP 407', isConnectionFailure: true);

  static const ipUnverified = WebViewFailure('Chưa xác minh được IP qua proxy',
      'Dịch vụ kiểm tra IP chưa trả về kết quả. Điều này chưa khẳng định proxy bị lỗi.');

  factory WebViewFailure.network(WebResourceError error,
      {required bool usingProxy}) {
    final code = RegExp(r'(?:net::)?(ERR_[A-Z0-9_]+)')
        .firstMatch(error.description)
        ?.group(1);
    final title = usingProxy ? 'Lỗi kết nối proxy' : 'Không thể mở TikTok';
    final via = usingProxy ? ' qua proxy' : '';
    String message;
    var connectionFailure = true;
    if (usingProxy &&
        (error.type == WebResourceErrorType.PROXY_AUTHENTICATION ||
            code == 'ERR_INVALID_AUTH_CREDENTIALS')) {
      return proxyAuth;
    } else if (code == 'ERR_PROXY_AUTH_UNSUPPORTED') {
      message = 'WebView không hỗ trợ kiểu xác thực của proxy này. '
          'Kiểm tra kiểu xác thực hoặc chọn proxy khác.';
    } else if (code == 'ERR_TUNNEL_CONNECTION_FAILED' ||
        code == 'ERR_HTTPS_PROXY_TUNNEL_RESPONSE') {
      message = 'Không tạo được đường hầm HTTPS qua proxy. '
          'Kiểm tra proxy, xác thực và quyền truy cập tới TikTok.';
    } else if (code == 'ERR_PROXY_CONNECTION_FAILED' ||
        code == 'ERR_NO_SUPPORTED_PROXIES') {
      message = 'Không kết nối được tới proxy. '
          'Kiểm tra địa chỉ, cổng và kết nối mạng.';
    } else if (error.type == WebResourceErrorType.TIMEOUT ||
        code == 'ERR_CONNECTION_TIMED_OUT' ||
        code == 'ERR_TIMED_OUT') {
      message = 'Kết nối$via quá thời gian chờ. '
          'Kiểm tra kết nối rồi thử lại.';
    } else if (error.type == WebResourceErrorType.HOST_LOOKUP ||
        code == 'ERR_NAME_NOT_RESOLVED') {
      message = 'Không phân giải được địa chỉ kết nối$via. '
          'Kiểm tra địa chỉ và mạng rồi thử lại.';
    } else if (error.type == WebResourceErrorType.CANNOT_CONNECT_TO_HOST ||
        error.type == WebResourceErrorType.NETWORK_CONNECTION_LOST ||
        code == 'ERR_CONNECTION_RESET' ||
        code == 'ERR_CONNECTION_CLOSED' ||
        code == 'ERR_INTERNET_DISCONNECTED') {
      message = 'Kết nối$via thất bại hoặc bị ngắt. '
          'Kiểm tra kết nối rồi thử lại.';
    } else if (error.type == WebResourceErrorType.FAILED_SSL_HANDSHAKE ||
        error.type == WebResourceErrorType.SECURE_CONNECTION_FAILED ||
        (code?.startsWith('ERR_CERT_') ?? false)) {
      message = 'Không thiết lập được kết nối HTTPS$via. '
          'Kiểm tra kết nối và chứng chỉ rồi thử lại.';
    } else {
      message = 'Không thể tải TikTok$via. '
          'Kiểm tra kết nối rồi thử lại.';
      connectionFailure = false;
    }
    return WebViewFailure(title, message,
        code: code, isConnectionFailure: connectionFailure);
  }

  factory WebViewFailure.http(int status) => status == 407
      ? proxyAuth
      : WebViewFailure('TikTok trả về lỗi',
          'Máy chủ trả về lỗi HTTP $status. Hãy thử tải lại trang.',
          code: 'HTTP $status');
}
