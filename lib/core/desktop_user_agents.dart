import 'firefox_user_agent.dart';

/// Android: one identity, Firefox for Android with "Desktop site" on.
const List<String> desktopUserAgents = [firefoxDesktopUserAgent];

/// The direct connection uses the same identity as every configuration.
Future<String> loadDirectDesktopUserAgent() async => firefoxDesktopUserAgent;

/// A new configuration's User-Agent; GeckoView offers only one.
Future<String> selectNextDesktopUserAgent() async => firefoxDesktopUserAgent;
