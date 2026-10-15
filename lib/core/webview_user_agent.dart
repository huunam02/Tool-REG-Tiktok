import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

bool get needsAndroidDesktopIdentity =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

String? androidChromeDesktopUserAgent(String nativeAgent) {
  final major = RegExp(r'Chrome/(\d+)\.').firstMatch(nativeAgent)?.group(1);
  if (major == null) return null;
  return 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
      '(KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36';
}

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
    // Match Chrome Android's desktop profile to the installed engine instead
    // of announcing a random Windows/macOS identity or an unrelated version.
    try {
      final nativeAgent =
          await (nativeAgentLoader ??
                  InAppWebViewController.getDefaultUserAgent)()
              .timeout(const Duration(seconds: 2));
      return androidChromeDesktopUserAgent(nativeAgent) ??
          androidChromeDesktopUserAgent(configuredAgent) ??
          configuredAgent;
    } catch (_) {
      // The native configure step must still succeed before any URL loads.
      return androidChromeDesktopUserAgent(configuredAgent) ?? configuredAgent;
    }
  }
  // A selected identity must reach the WebView unchanged. Deriving Safari
  // from the same device on every launch collapsed different proxy UAs into
  // one string on iOS. Native discovery is only a fallback for a missing UA.
  if (configuredAgent.trim().isNotEmpty ||
      kIsWeb ||
      defaultTargetPlatform != TargetPlatform.iOS) {
    return configuredAgent;
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
