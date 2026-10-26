import 'package:flutter/foundation.dart';

import 'chrome_user_agent.dart';

bool get needsAndroidDesktopIdentity =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The identity the app's own requests (proxy IP, time zone) announce: the
/// same Chrome desktop-site User-Agent that the WebView sends.
Future<String> resolveWebViewUserAgent(String configuredAgent) async =>
    chromeDesktopUserAgent;
