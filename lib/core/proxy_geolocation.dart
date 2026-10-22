import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

import 'app_configuration.dart';

class ProxyGeolocation {
  const ProxyGeolocation({required this.ip, required this.timeZoneId});

  final String ip;
  final String timeZoneId;

  factory ProxyGeolocation.fromJson(dynamic data) {
    final zone = data is Map && data['timezone'] is Map ? data['timezone']['id'] : null;
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

/// Reads geolocation through the already active Android VPN tunnel.
class ProxyGeolocationLookup {
  ProxyGeolocationLookup({this.timeout = const Duration(seconds: 12)});

  final Duration timeout;
  final http.Client _client = http.Client();
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Future<ProxyGeolocation> lookup({
    required WebViewProxy proxy,
    required String userAgent,
    bool useInstalledEngine = true,
  }) async {
    if (_cancelled) throw const FormatException('Đã hủy kiểm tra múi giờ.');
    try {
      final response = await _client
          .get(
            Uri.parse('https://ipwho.is/?fields=success,ip,timezone.id'),
            headers: {'Cache-Control': 'no-cache', 'User-Agent': userAgent},
          )
          .timeout(timeout);
      if (_cancelled) throw const FormatException('Đã hủy kiểm tra múi giờ.');
      if (response.statusCode != 200) {
        throw FormatException('API múi giờ trả về HTTP ${response.statusCode}.');
      }
      return ProxyGeolocation.fromJson(jsonDecode(response.body));
    } on TimeoutException {
      throw const FormatException('Kiểm tra múi giờ qua proxy quá thời gian chờ.');
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('Không thể kiểm tra múi giờ qua proxy SOCKS5.');
    }
  }
}
