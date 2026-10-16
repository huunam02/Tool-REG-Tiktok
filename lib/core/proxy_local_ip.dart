import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_configuration.dart';

const defaultSimulatedLocalIp = '192.168.1.10';
const _profilesKey = 'webview_proxy_local_ips_v1';
Future<void>? _queue;

bool isSimulatedLocalIp(String value) {
  final parts = value.split('.');
  if (parts.length != 4 || parts[0] != '192' || parts[1] != '168') {
    return false;
  }
  final subnet = int.tryParse(parts[2]);
  final host = int.tryParse(parts[3]);
  return subnet != null &&
      host != null &&
      subnet >= 0 &&
      subnet <= 255 &&
      host >= 1 &&
      host <= 254 &&
      value == '192.168.$subnet.$host';
}

/// Persist one random private address per scheme/host/port. Credentials and
/// account data are excluded; rotating a proxy password keeps its local IP.
Future<String> loadProxyLocalIp(WebViewProxy? proxy) async {
  if (proxy == null) return defaultSimulatedLocalIp;
  final previous = _queue;
  final finished = Completer<void>();
  _queue = finished.future;
  if (previous != null) await previous;
  try {
    final preferences = await SharedPreferences.getInstance();
    final profiles = <String, String>{};
    try {
      final decoded = jsonDecode(preferences.getString(_profilesKey) ?? '{}');
      if (decoded is Map) {
        for (final entry in decoded.entries) {
          if (entry.key is String &&
              entry.value is String &&
              isSimulatedLocalIp(entry.value as String)) {
            profiles[entry.key as String] = entry.value as String;
          }
        }
      }
    } on FormatException {
      // Rebuild a damaged mapping rather than emitting an invalid address.
    }
    final key = jsonEncode([
      proxy.uri.scheme.toLowerCase(),
      proxy.uri.host.toLowerCase(),
      proxy.uri.port,
    ]);
    final stored = profiles[key];
    if (stored != null) return stored;
    final used = {...profiles.values, defaultSimulatedLocalIp};
    const count = 256 * 254;
    final start = Random.secure().nextInt(count);
    for (var offset = 0; offset < count; offset++) {
      final index = (start + offset) % count;
      final address = '192.168.${index ~/ 254}.${index % 254 + 1}';
      if (used.contains(address)) continue;
      profiles[key] = address;
      if (!await preferences.setString(_profilesKey, jsonEncode(profiles))) {
        throw StateError('Không lưu được Local IP mô phỏng của proxy.');
      }
      return address;
    }
    throw StateError('Đã dùng hết dải Local IP mô phỏng.');
  } finally {
    if (identical(_queue, finished.future)) _queue = null;
    finished.complete();
  }
}
