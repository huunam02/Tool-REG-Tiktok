import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'chrome_user_agent.dart';

bool get needsAndroidDesktopIdentity =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String get currentAndroidChromeDesktopUserAgent =>
    chromeDesktopUserAgent('X11; Linux x86_64');

String androidChromeDesktopUserAgent(String configuredAgent) =>
    chromeDesktopUserAgent(
      'X11; Linux x86_64',
      major: recentChromeMajorForUserAgent(configuredAgent),
    );

/// Complete native Client Hints configuration before the first navigation.
Future<void> configureAndroidDesktopIdentity(
  InAppWebViewController controller, {
  required String userAgent,
}) async {
  if (!needsAndroidDesktopIdentity) return;
  await const MethodChannel(
    'test_tiktok/webview_identity',
  ).invokeMethod<String>('configure', {
    'id': controller.platform.params.id,
    'userAgent': userAgent,
    'chromeFullVersion': chromeFullVersionForUserAgent(userAgent),
  });
}

/// Keep a desktop identity while matching the WebKit engine used on iOS.
/// WebKit's UA supplies the engine version. Prefer Safari's Version token if
/// present; otherwise use the iOS version as the Safari compatibility version.
String? safariDesktopUserAgent(String nativeAgent) {
  if (RegExp(r'Chrome/|Chromium/|Edg/').hasMatch(nativeAgent)) return null;
  final webkit = RegExp(
    r'AppleWebKit/(\d+(?:\.\d+)+)',
  ).firstMatch(nativeAgent)?.group(1);
  final version =
      RegExp(r'Version/(\d+(?:\.\d+)*)').firstMatch(nativeAgent)?.group(1) ??
      RegExp(
        r'CPU(?: iPhone)? OS (\d+(?:_\d+)*)',
      ).firstMatch(nativeAgent)?.group(1)?.replaceAll('_', '.');
  if (webkit == null || version == null) return null;
  return 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
      'AppleWebKit/$webkit (KHTML, like Gecko) '
      'Version/$version Safari/$webkit';
}

Future<String> resolveWebViewUserAgent(
  String configuredAgent, {
  Future<String> Function()? nativeAgentLoader,
}) async {
  if (needsAndroidDesktopIdentity) {
    // A configured Chrome version changes the advertised identity, not the
    // installed Chromium engine. Native Client Hints use the same version.
    return androidChromeDesktopUserAgent(configuredAgent);
  }
  // A selected identity must reach the WebView unchanged. Deriving Safari
  // from the same device on every launch collapsed different proxy UAs into
  // one string on iOS. Native discovery is only a fallback for a missing UA.
  if (configuredAgent.trim().isNotEmpty ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS) {
    return normalizeDesktopUserAgentForPlatform(configuredAgent);
  }
  try {
    final nativeAgent =
        await (nativeAgentLoader ??
                InAppWebViewController.getDefaultUserAgent)()
            .timeout(const Duration(seconds: 2));
    return safariDesktopUserAgent(nativeAgent) ?? configuredAgent;
  } catch (_) {
    // Preserve the configured desktop UA if native discovery is unavailable.
    return configuredAgent;
  }
}
