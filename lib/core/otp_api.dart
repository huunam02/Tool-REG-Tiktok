import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'config.dart' as config;

const defaultOtpApiUrl = config.otpApiUrl;

class OtpApiConfiguration {
  const OtpApiConfiguration({
    required this.url,
    required this.readerToken,
    this.waitSeconds = 180,
  });

  final Uri url;
  final String readerToken;
  final int waitSeconds;

  static bool isEmail(String value) =>
      RegExp(r'^[^\s@|]+@[^\s@|]+\.[^\s@|]+$').hasMatch(value.trim());

  static Uri parseUrl(String value) {
    final url = Uri.tryParse(value.trim());
    if (url == null ||
        (url.scheme != 'http' && url.scheme != 'https') ||
        url.host.isEmpty ||
        url.userInfo.isNotEmpty ||
        url.hasFragment) {
      throw const FormatException('Nhập URL API HTTP/HTTPS hợp lệ.');
    }
    return url;
  }
}

class OtpApiException implements Exception {
  const OtpApiException(this.message);

  // Only local, fixed messages are shown; API errors may contain credentials.
  final String message;
}

abstract class OtpCodeReader {
  Future<String> fetchCode({required String email, required String password});
  void close();
}

class OtpApiClient implements OtpCodeReader {
  OtpApiClient(this.configuration,
      {http.Client? client, void Function(String)? logOutput})
      : _client = client ?? http.Client(),
        _logOutput = logOutput ?? ((message) => debugPrint(message));

  final OtpApiConfiguration configuration;
  final http.Client _client;
  final _abort = Completer<void>();
  final void Function(String) _logOutput;

  @override
  Future<String> fetchCode(
      {required String email, required String password}) async {
    if (!OtpApiConfiguration.isEmail(email) || password.isEmpty) {
      _log('ERROR', {'reason': 'Missing or invalid mailbox credentials'});
      throw const OtpApiException(
          'Hãy nhập email và mật khẩu hộp thư để lấy OTP.');
    }
    if (configuration.readerToken.trim().isEmpty) {
      _log('ERROR', {'reason': 'Missing reader token'});
      throw const OtpApiException('Hãy nhập token của API lấy OTP.');
    }
    try {
      return await _fetch(email.trim(), password)
          .timeout(Duration(seconds: configuration.waitSeconds + 15));
    } on TimeoutException {
      _log('ERROR', {
        'reason': 'Request timed out',
        'timeoutSeconds': configuration.waitSeconds + 15,
      });
      close();
      throw const OtpApiException(
          'Hết thời gian chờ API lấy OTP. Bạn có thể nhập mã thủ công.');
    } on http.RequestAbortedException {
      _log('CANCELLED', {'reason': 'Request cancelled'});
      throw const OtpApiException('Đã dừng yêu cầu lấy OTP.');
    } on OtpApiException catch (error) {
      _log('ERROR', {'reason': error.message});
      rethrow;
    } catch (error) {
      // Exception messages can echo the request, so log only their type.
      _log('ERROR',
          {'reason': 'Connection failed', 'type': '${error.runtimeType}'});
      throw const OtpApiException(
          'Không kết nối được API lấy OTP. Hãy kiểm tra mạng và URL API.');
    }
  }

  Future<String> _fetch(String email, String password) async {
    final stopwatch = Stopwatch()..start();
    final requestBody = {
      'email': '$email|$password',
      'wait': configuration.waitSeconds,
    };
    _log('REQUEST', {
      'method': 'POST',
      'url': _redact(
          '${configuration.url.origin}${configuration.url.path}', password),
      'headers': {
        'Content-Type': 'application/json',
        'X-Reader-Token': '***',
        'ngrok-skip-browser-warning': '1',
      },
      'data': {'email': '$email|***', 'wait': configuration.waitSeconds},
    });
    final request = http.AbortableRequest('POST', configuration.url,
        abortTrigger: _abort.future);
    // Do not forward the reader token or mailbox credentials to a redirect.
    request.followRedirects = false;
    request.headers.addAll({
      'Content-Type': 'application/json',
      'X-Reader-Token': configuration.readerToken,
      'ngrok-skip-browser-warning': '1',
    });
    request.body = jsonEncode(requestBody);
    final response = await _client.send(request);
    final rawBody = await const Utf8Decoder(allowMalformed: true)
        .bind(response.stream)
        .join();
    dynamic body;
    var validJson = true;
    try {
      body = jsonDecode(rawBody);
    } catch (_) {
      validJson = false;
      body = rawBody;
    }
    _log('RESPONSE', {
      'statusCode': response.statusCode,
      'elapsedMs': stopwatch.elapsedMilliseconds,
      'data': _redact(body, password),
    });
    switch (response.statusCode) {
      case 401:
      case 403:
        throw const OtpApiException('Token của API lấy OTP không hợp lệ.');
      case 408:
        throw const OtpApiException(
            'API chưa tìm thấy OTP trong thời gian chờ. Bạn có thể nhập mã thủ công.');
      case 409:
        throw const OtpApiException(
            'Hộp thư yêu cầu xác minh hoặc mật khẩu không đúng. Hãy kiểm tra hộp thư.');
      case 400:
      case 422:
        throw const OtpApiException(
            'API không chấp nhận thông tin hộp thư. Hãy kiểm tra email và mật khẩu hộp thư.');
    }
    if (response.statusCode != 200) {
      throw const OtpApiException('API lấy OTP đang lỗi. Hãy thử lại sau.');
    }
    if (!validJson) {
      throw const OtpApiException('API lấy OTP trả về dữ liệu không hợp lệ.');
    }
    final code = body is Map ? body['code'] : null;
    if (body is! Map ||
        body['ok'] != true ||
        code is! String ||
        !RegExp(r'^[0-9]{6}$').hasMatch(code.trim())) {
      throw const OtpApiException('API chưa trả về mã OTP 6 chữ số hợp lệ.');
    }
    return code.trim();
  }

  void _log(String event, Map<String, dynamic> data) {
    if (!kDebugMode) return;
    _logOutput(
        '[OTP API] $event\n${const JsonEncoder.withIndent('  ').convert(data)}');
  }

  dynamic _redact(dynamic value, String password) {
    String redactText(String text) {
      for (final secret in [password, configuration.readerToken]) {
        if (secret.isNotEmpty) text = text.replaceAll(secret, '***');
      }
      return text;
    }

    if (value is Map) {
      return value.map((key, nested) {
        final name = key.toString();
        final normalized = name.toLowerCase().replaceAll(RegExp('[^a-z]'), '');
        final sensitive = normalized.contains('password') ||
            normalized.contains('token') ||
            normalized.contains('authorization');
        final sanitized = sensitive
            ? '***'
            : normalized == 'email' && nested is String && nested.contains('|')
                ? '${redactText(nested.split('|').first)}|***'
                : _redact(nested, password);
        return MapEntry(redactText(name), sanitized);
      });
    }
    if (value is List) {
      return value.map((item) => _redact(item, password)).toList();
    }
    if (value is String) return redactText(value);
    return value;
  }

  @override
  void close() {
    if (!_abort.isCompleted) _abort.complete();
    _client.close();
  }
}

/// One API request per challenge; cancellation discards any late response.
class OtpCodeRequest {
  OtpCodeRequest.start(this._reader,
      {required String email, required String password}) {
    unawaited(_fetch(email, password));
  }

  final OtpCodeReader _reader;
  bool _cancelled = false;
  String? code;
  String? error;

  Future<void> _fetch(String email, String password) async {
    try {
      final value = await _reader.fetchCode(email: email, password: password);
      if (!_cancelled) code = value;
    } on OtpApiException catch (failure) {
      if (!_cancelled) error = failure.message;
    } catch (_) {
      if (!_cancelled) error = 'Không thể lấy OTP từ API. Hãy thử lại sau.';
    } finally {
      _reader.close();
    }
  }

  void cancel() {
    _cancelled = true;
    _reader.close();
  }
}
