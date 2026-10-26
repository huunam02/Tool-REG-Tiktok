import 'package:flutter/services.dart';

/// The only browser identity: Chrome for Android with "Desktop site" on, at
/// the installed System WebView's Chromium version (native sets the same UA
/// and Client Hints on the WebView). [loadChromeDesktopUserAgent] replaces
/// this fallback at startup, so the app's own requests match the page.
String chromeDesktopUserAgent = chromeDesktopUserAgentFor(140);

String chromeDesktopUserAgentFor(int major) =>
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36';

Future<void> loadChromeDesktopUserAgent() async {
  try {
    final agent = await const MethodChannel(
      'test_tiktok/device',
    ).invokeMethod<String>('webViewUserAgent');
    if (agent != null && agent.isNotEmpty) chromeDesktopUserAgent = agent;
  } on PlatformException catch (_) {
    // WebView missing or disabled; the browser view reports it.
  } on MissingPluginException catch (_) {}
}

/// The WebView never sends a stored Firefox, Edge, Miui or hand-typed
/// identity, so every saved User-Agent reads as the Chrome one.
String normalizeDesktopUserAgentForPlatform(String agent) =>
    chromeDesktopUserAgent;
