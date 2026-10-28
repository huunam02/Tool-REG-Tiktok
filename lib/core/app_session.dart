import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'account_sessions.dart';

/// Local indication only; the live TikTok page still confirms authentication.
Future<bool> hasTikTokLoginSession({DateTime? now}) async {
  if (kIsWeb) return false;
  return AccountSessions.currentIsLoggedIn();
}

Future<void> clearAppSession() async {
  if (kIsWeb) throw UnsupportedError('Native Gecko session required');
  await const MethodChannel(
    'test_tiktok/gecko_storage',
  ).invokeMethod<void>('clearAll');
  await AccountSessions.clearMarkers();
}
