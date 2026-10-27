/// Firefox Windows identity from the supplied WhatIsMyBrowser readout.
/// Keep [geckoViewMajor] in step with android/app/build.gradle and the native
/// FirefoxDesktopIdentity. GeckoView remains an Android engine.
const geckoViewMajor = 158;
const firefoxDesktopUserAgent =
    'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:$geckoViewMajor.0) '
    'Gecko/20100101 Firefox/$geckoViewMajor.0';

const firefoxDesktopGpuLabel = 'Windows 10 · AMD Radeon R9 200 Series';
const firefoxDesktopTimeZone = 'Asia/Ho_Chi_Minh';

/// GeckoView never sends a stored Chrome, Edge, Miui or hand-typed identity,
/// so every saved User-Agent reads as the Firefox one.
String normalizeDesktopUserAgentForPlatform(String agent) =>
    firefoxDesktopUserAgent;
