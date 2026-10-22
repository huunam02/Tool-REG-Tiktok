import 'package:flutter/foundation.dart';

import 'firefox_user_agent.dart';

bool get needsAndroidDesktopIdentity =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

/// The identity the app's own requests (proxy IP, time zone) announce: the
/// same Firefox desktop-mode User-Agent that GeckoView sends.
Future<String> resolveWebViewUserAgent(String configuredAgent) async =>
    firefoxDesktopUserAgent;
