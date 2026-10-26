import 'chrome_user_agent.dart';

/// Android: one identity, Chrome for Android with "Desktop site" on.
List<String> get desktopUserAgents => [chromeDesktopUserAgent];

/// The direct connection uses the same identity as every configuration.
Future<String> loadDirectDesktopUserAgent() async => chromeDesktopUserAgent;

/// A new configuration's User-Agent; the WebView offers only one.
Future<String> selectNextDesktopUserAgent() async => chromeDesktopUserAgent;
