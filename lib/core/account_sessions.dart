import 'dart:convert';

import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_session.dart';

/// TikTok cookie jars keyed by configuration ID and account identity.
/// Only one jar is mounted in the native WebView store at a time. Callers must
/// dispose the previous account's WebView before switching.
class AccountSessions {
  static const _ownerKey = 'tiktok_session_owner_v1';
  static String _identity(int id, String email) => '$id:${email.trim()}';
  static String _jarKey(int id) => 'tiktok_cookie_jar_v1_$id';
  static final _url = WebUri('https://www.tiktok.com/');

  static Future<void> _write(
    SharedPreferences prefs,
    String key,
    String value,
  ) async {
    if (!await prefs.setString(key, value)) {
      throw StateError('Could not persist account session');
    }
  }

  static Future<void> save(int id, String email) async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_ownerKey);
    final identity = _identity(id, email);
    // A switch interrupted by a crash must never attach another jar to this ID.
    if (owner != null && owner != identity) return;
    final cookies = await CookieManager().getCookies(url: _url);
    if (prefs.getString(_ownerKey) != owner) return;
    await _write(
      prefs,
      _jarKey(id),
      jsonEncode({
        'identity': identity,
        'cookies': cookies.map((cookie) => cookie.toMap()).toList(),
      }),
    );
    if (prefs.getString(_ownerKey) != owner) return;
    await _write(prefs, _ownerKey, identity);
  }

  static Future<void> activate(
    int id,
    String email, {
    Future<void> Function() clear = clearAppSession,
    bool fresh = false,
    bool adoptLegacy = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final identity = _identity(id, email);
    if (!fresh &&
        adoptLegacy &&
        prefs.getString(_ownerKey) == null &&
        await hasTikTokLoginSession()) {
      await save(id, email);
    }
    if (!fresh &&
        prefs.getString(_ownerKey) == identity &&
        await hasTikTokLoginSession()) {
      return;
    }
    // Persist this before clearing so an interrupted restore cannot be saved
    // back under the previous configuration on the next launch.
    await _write(prefs, _ownerKey, 'switching');
    await clear();
    if (fresh && !await prefs.remove(_jarKey(id))) {
      throw StateError('Could not reset account session');
    }
    final raw = fresh ? null : prefs.getString(_jarKey(id));
    if (raw != null) {
      final jar = jsonDecode(raw) as Map<String, dynamic>;
      if (jar['identity'] == identity) {
        final now = DateTime.now().millisecondsSinceEpoch;
        for (final item in jar['cookies'] as List) {
          final cookie = Cookie.fromMap(
            Map<String, dynamic>.from(item as Map),
          )!;
          if (cookie.value is! String ||
              (cookie.value as String).isEmpty ||
              (cookie.expiresDate != null && cookie.expiresDate! <= now)) {
            continue;
          }
          final domain = cookie.domain;
          if (domain != null &&
              domain != 'tiktok.com' &&
              !domain.endsWith('.tiktok.com')) {
            continue;
          }
          final ok = await CookieManager().setCookie(
            url: _url,
            name: cookie.name,
            value: cookie.value as String,
            domain: domain,
            path: cookie.path ?? '/',
            expiresDate: cookie.expiresDate,
            isSecure: cookie.isSecure ?? true,
            isHttpOnly:
                cookie.isHttpOnly ??
                const {
                  'sid_tt',
                  'sessionid',
                  'sessionid_ss',
                }.contains(cookie.name),
            sameSite: cookie.sameSite,
          );
          if (!ok) throw StateError('Could not restore account cookie');
        }
      }
    }
    await _write(prefs, _ownerKey, identity);
  }

  static Future<void> delete(int id) async {
    final prefs = await SharedPreferences.getInstance();
    if (!await prefs.remove(_jarKey(id))) {
      throw StateError('Could not remove account session');
    }
  }
}
