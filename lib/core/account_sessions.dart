import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app_session.dart';

/// Gecko partitions cookies and DOM storage natively by this context ID.
String geckoProfileContextId(int id) => 'profile-$id';

class AccountSessions {
  static const _ownerKey = 'tiktok_session_owner_v2';
  static const _storage = MethodChannel('test_tiktok/gecko_storage');
  static String _identity(int id, String email) => '$id:${email.trim()}';
  static String _validKey(int id) => 'tiktok_gecko_session_valid_$id';

  /// The context itself is persistent; this only marks a confirmed live login.
  static Future<void> save(int id, String email) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_ownerKey, _identity(id, email));
    await prefs.setBool(_validKey(id), true);
  }

  static Future<void> activate(
    int id,
    String email, {
    Future<void> Function() clear = clearAppSession,
    bool fresh = false,
    bool adoptLegacy = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    if (fresh) {
      await _storage.invokeMethod<void>('clearContext', {
        'contextId': geckoProfileContextId(id),
      });
      await prefs.setBool(_validKey(id), false);
    }
    await prefs.setString(_ownerKey, _identity(id, email));
  }

  static Future<void> delete(int id) async {
    await _storage.invokeMethod<void>('clearContext', {
      'contextId': geckoProfileContextId(id),
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_validKey(id));
    if (prefs.getString(_ownerKey)?.startsWith('$id:') == true) {
      await prefs.remove(_ownerKey);
    }
  }

  static Future<bool> currentIsLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    final owner = prefs.getString(_ownerKey);
    final id = owner == null ? null : int.tryParse(owner.split(':').first);
    return id != null && (prefs.getBool(_validKey(id)) ?? false);
  }

  static Future<void> clearMarkers() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_ownerKey);
  }
}
