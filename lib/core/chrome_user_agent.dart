// Chrome desktop stable, verified against Chrome Releases on 2026-10-15.
const currentChromeMajor = 155;
const currentChromeFullVersion = '155.0.8059.79';
const linuxChromePlatform = 'X11; Linux x86_64';
const windowsChromePlatform = 'Windows NT 10.0; Win64; x64';
String get windowsChromeUserAgent =>
    chromeDesktopUserAgent(windowsChromePlatform);

bool isWindowsChromeUserAgent(String agent) =>
    agent.contains('($windowsChromePlatform)') && agent.contains('Chrome/');

const desktopChromePlatform = linuxChromePlatform;
const recentChromeFullVersions = <int, String>{
  151: '151.0.7922.173',
  152: '152.0.7977.64',
  153: '153.0.8010.47',
  154: '154.0.8037.97',
  155: currentChromeFullVersion,
};

// Additional Android browser profile based on the supplied Miui sample.
// Use a desktop platform as well as a desktop viewport: Android in the UA
// can make websites choose their phone experience even without Mobile.
const miuiChromeFullVersion = '135.0.7049.79';
const miuiBrowserUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 '
    '(KHTML, like Gecko) Chrome/135.0.7049.79 Safari/537.36 '
    'XiaoMi/MiuiBrowser/14.65.0-gn';

bool isMiuiBrowserUserAgent(String agent) =>
    agent.contains('XiaoMi/MiuiBrowser/');

String chromeDesktopUserAgent(
  String platform, {
  int major = currentChromeMajor,
}) =>
    'Mozilla/5.0 ($platform) AppleWebKit/537.36 (KHTML, like Gecko) '
    'Chrome/$major.0.0.0 Safari/537.36';

int recentChromeMajorForUserAgent(String agent) {
  final token = RegExp(r'Chrome/(\d+)\.').firstMatch(agent)?.group(1);
  final major = token == null ? null : int.tryParse(token);
  return recentChromeFullVersions.containsKey(major)
      ? major!
      : currentChromeMajor;
}

String chromeFullVersionForUserAgent(String agent) =>
    isMiuiBrowserUserAgent(agent)
    ? miuiChromeFullVersion
    : recentChromeFullVersions[recentChromeMajorForUserAgent(agent)]!;

/// Normalize existing Chrome/Edge desktop identities without changing custom
/// non-Chromium strings. Supported Chrome versions retain their selected major.
String normalizeDesktopUserAgentForPlatform(String agent) {
  if (isMiuiBrowserUserAgent(agent)) {
    return miuiBrowserUserAgent;
  }
  final chrome = RegExp(
    r'^Mozilla/5\.0 \((?:X11; Linux x86_64|Windows[^)]*|Macintosh[^)]*)\) '
    r'AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/\d+(?:\.\d+){3} Safari/537\.36'
    r'(?: Edg/\d+(?:\.\d+){3})?$',
  );
  return chrome.hasMatch(agent)
      ? chromeDesktopUserAgent(
          isWindowsChromeUserAgent(agent)
              ? windowsChromePlatform
              : desktopChromePlatform,
          major: recentChromeMajorForUserAgent(agent),
        )
      : agent;
}

// Upgrade only the old built-in templates. Keep manually entered identities.
String upgradeLegacyDesktopUserAgent(String agent) {
  final match = RegExp(
    r'^Mozilla/5\.0 \((X11; Linux x86_64|Windows NT 10\.0; Win64; x64|Macintosh; Intel Mac OS X 10_15_7)\) '
    r'AppleWebKit/537\.36 \(KHTML, like Gecko\) Chrome/(12\d|13\d|140)\.0\.0\.0 Safari/537\.36'
    r'(?: Edg/\2\.0\.0\.0)?$',
  ).firstMatch(agent);
  return match == null ? agent : chromeDesktopUserAgent(match.group(1)!);
}
