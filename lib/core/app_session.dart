import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

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
