import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

/// Checks the public address through Android's active per-app VPN.
class WebViewProxyIpChecker {
  WebViewProxyIpChecker({this.timeout = const Duration(seconds: 8)});

  final Duration timeout;
  final http.Client _client = http.Client();
  bool _cancelled = false;

  void cancel() {
    _cancelled = true;
    _client.close();
  }

  Future<String?> check({required String userAgent}) async {
    for (final host in ['api.ipify.org', 'api64.ipify.org']) {
      if (_cancelled) return null;
      try {
        final response = await _client
            .get(
              Uri.https(host, '/', {
                'format': 'json',
                '_': DateTime.now().microsecondsSinceEpoch.toString(),
              }),
              headers: {'Cache-Control': 'no-cache', 'User-Agent': userAgent},
            )
            .timeout(timeout);
        if (response.statusCode != 200) continue;
        final data = jsonDecode(response.body);
        final ip = data is Map ? data['ip'] : null;
        if (ip is String && InternetAddress.tryParse(ip) != null) return ip;
      } catch (_) {
        if (_cancelled) return null;
      }
    }
    return null;
  }
}
