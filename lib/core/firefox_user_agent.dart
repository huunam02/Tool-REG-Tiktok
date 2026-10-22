/// The only browser identity: Firefox for Android with "Desktop site" on,
/// exactly what GeckoView sends to TikTok. Keep [geckoViewMajor] in step
/// with the geckoview dependency in android/app/build.gradle.
const geckoViewMajor = 158;
const firefoxDesktopUserAgent =
    'Mozilla/5.0 (X11; Linux x86_64; rv:$geckoViewMajor.0) '
    'Gecko/20100101 Firefox/$geckoViewMajor.0';

/// GeckoView never sends a stored Chrome, Edge, Miui or hand-typed identity,
/// so every saved User-Agent reads as the Firefox one.
String normalizeDesktopUserAgentForPlatform(String agent) =>
    firefoxDesktopUserAgent;
