import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:shared_preferences/shared_preferences.dart';

import 'app_configuration.dart';

const defaultSimulatedLocalIp = '192.168.1.10';
const _profilesKey = 'webview_proxy_local_ips_v1';
Future<void>? _queue;

/// Private LAN ranges: 10.0.0.0/8, 172.16.0.0/12 and 192.168.0.0/16.
/// Host .0 and .255 are excluded, and the address must be canonical.
bool isSimulatedLocalIp(String value) {
  final parts = value.split('.');
  if (parts.length != 4) return false;
  final octets = parts.map(int.tryParse).toList();
  if (octets.any((octet) => octet == null || octet < 0 || octet > 255) ||
      octets.join('.') != value) {
    return false;
  }
  final [a, b, _, host] = octets.cast<int>();
  final private =
      a == 10 || (a == 172 && b >= 16 && b <= 31) || (a == 192 && b == 168);
  return private && host >= 1 && host <= 254;
}

/// Pick one private range evenly, then a random address inside it.
String _randomSimulatedLocalIp(Random random) {
  final host = random.nextInt(254) + 1;
  final subnet = random.nextInt(256);
  return switch (random.nextInt(3)) {
    0 => '10.${random.nextInt(256)}.$subnet.$host',
    1 => '172.${16 + random.nextInt(16)}.$subnet.$host',
    _ => '192.168.$subnet.$host',
  };
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
    final random = Random.secure();
    // Millions of addresses remain, so a fresh one is found almost at once.
    for (var attempt = 0; attempt < 1000; attempt++) {
      final address = _randomSimulatedLocalIp(random);
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
