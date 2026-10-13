import 'dart:math';

import 'config.dart' as defaults;
import 'otp_api.dart';

/// A snapshot of Home's configuration for one TikTok screen.
class AppConfiguration {
  AppConfiguration({
    required this.userAgent,
    required this.signupEmail,
    required this.signupPassword,
    required this.loginUsername,
    required this.loginPassword,
    required List<String> comments,
    this.signupOtp = '',
    this.loginOtp = '',
    this.signupMailboxPassword = '',
    this.loginMailboxPassword = '',
    this.otpApi,
    this.birthday,
    this.proxy,
  }) : comments = List.unmodifiable(comments);

  factory AppConfiguration.defaults(String userAgent) => AppConfiguration(
        userAgent: userAgent,
        signupEmail: defaults.emailSignup,
        signupPassword: defaults.passwordSignup,
        loginUsername: defaults.email,
        loginPassword: defaults.password,
        comments: defaults.defaultAutoComments,
      );

  final String userAgent;
  final String signupEmail;
  final String signupPassword;
  final String loginUsername;
  final String loginPassword;
  final String signupOtp;
  final String loginOtp;
  final String signupMailboxPassword;
  final String loginMailboxPassword;
  final OtpApiConfiguration? otpApi;
  final List<String> comments;
  final DateTime? birthday;
  final WebViewProxy? proxy;

  static List<String> parseComments(String value) => value
      .split('\n')
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();

  static DateTime randomSignupBirthday({Random? random}) {
    final generator = random ?? Random();
    final year = 1960 + generator.nextInt(2004 - 1960 + 1);
    final month = 1 + generator.nextInt(12);
    final daysInMonth = DateTime.utc(year, month + 1, 0).day;
    return DateTime(year, month, 1 + generator.nextInt(daysInMonth));
  }

  static DateTime? parseBirthday(String value) {
    final date = DateTime.tryParse(value);
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value) ||
        date == null ||
        date.year < 1900 ||
        date.isAfter(DateTime.now()) ||
        formatBirthday(date) != value) {
      return null;
    }
    return date;
  }

  static String formatBirthday(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

class WebViewProxy {
  const WebViewProxy(
      {required this.uri, this.username = '', this.password = ''});

  final Uri uri;
  final String username;
  final String password;

  /// Import host:port:username:password; the name is supplied separately.
  static WebViewProxy parseImport(String value) {
    final line = value.replaceAll(RegExp(r'^[\r\n]+|[\r\n]+$'), '');
    final match =
        RegExp(r'^([^:\r\n]+):(\d+):([^:\r\n]+):([^\r\n]+)$').firstMatch(line);
    if (match == null ||
        match.group(3)!.trim().isEmpty ||
        match.group(4)!.trim().isEmpty) {
      throw const FormatException(
          'Nhập một dòng proxy dạng host:port:username:password.');
    }
    return parse('${match.group(1)!.trim()}:${match.group(2)}',
        username: match.group(3)!, password: match.group(4)!)!;
  }

  static WebViewProxy? parse(String value,
      {String username = '', String password = ''}) {
    value = value.trim();
    if (value.isEmpty) return null;
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null ||
        !const ['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        RegExp(r'\s').hasMatch(value) ||
        !RegExp(r':\d+/?$').hasMatch(value) ||
        uri.port < 1 ||
        uri.port > 65535 ||
        uri.userInfo.isNotEmpty ||
        (uri.path.isNotEmpty && uri.path != '/') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const FormatException('Nhập proxy HTTP/HTTPS dạng host:port.');
    }
    return WebViewProxy(
      uri: uri.replace(path: ''),
      username: username.trim(),
      password: password,
    );
  }
}
