import 'package:flutter/foundation.dart';

import 'chrome_user_agent.dart';

bool get needsAndroidDesktopIdentity =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String get currentAndroidChromeDesktopUserAgent =>
    chromeDesktopUserAgent('X11; Linux x86_64');

String androidChromeDesktopUserAgent(String configuredAgent) =>
    isMiuiBrowserUserAgent(configuredAgent)
    ? miuiBrowserUserAgent
    : chromeDesktopUserAgent(
        isWindowsChromeUserAgent(configuredAgent)
            ? windowsChromePlatform
            : linuxChromePlatform,
        major: recentChromeMajorForUserAgent(configuredAgent),
      );

Future<String> resolveWebViewUserAgent(String configuredAgent) async =>
    androidChromeDesktopUserAgent(configuredAgent);
