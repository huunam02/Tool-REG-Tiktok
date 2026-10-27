import 'firefox_user_agent.dart';

/// Android: one configured identity, Firefox 158 on Windows 10.
const List<String> desktopUserAgents = [firefoxDesktopUserAgent];

/// The direct connection uses the same identity as every configuration.
Future<String> loadDirectDesktopUserAgent() async => firefoxDesktopUserAgent;

/// A new configuration's User-Agent; GeckoView offers only one.
Future<String> selectNextDesktopUserAgent() async => firefoxDesktopUserAgent;
