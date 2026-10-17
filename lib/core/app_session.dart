import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

/// Local indication only; confirm the live TikTok page before resuming work.
Future<bool> hasTikTokLoginSession({DateTime? now}) async {
  if (kIsWeb) return false;
  try {
    final cookies = await CookieManager().getCookies(
      url: WebUri('https://www.tiktok.com/'),
    );
    final timestamp = (now ?? DateTime.now()).millisecondsSinceEpoch;
    return cookies.any(
      (cookie) =>
          const {'sid_tt', 'sessionid', 'sessionid_ss'}.contains(cookie.name) &&
          cookie.value is String &&
          (cookie.value as String).trim().isNotEmpty &&
          (cookie.expiresDate == null || cookie.expiresDate! > timestamp),
    );
  } catch (_) {
    // Cookie access can be unavailable during platform initialization.
    return false;
  }
}

/// Clear cookies, local/session storage and WebView cache without changing UA.
Future<void> clearAppSession() async {
  if (kIsWeb) throw UnsupportedError('Native WebView session required');

  await CookieManager.instance().deleteAllCookies();
  final storage = WebStorageManager.instance();
  switch (defaultTargetPlatform) {
    case TargetPlatform.android:
      await storage.deleteAllData();
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      await storage.removeDataModifiedSince(
        dataTypes: WebsiteDataType.ALL,
        date: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    default:
      throw UnsupportedError('Session reset is supported on Android/iOS/macOS');
  }
  await InAppWebViewController.clearAllCache();
}
