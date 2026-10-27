package com.brisklane.browser.gecko

import org.mozilla.geckoview.GeckoPreferenceController
import org.mozilla.geckoview.GeckoPreferenceController.SetGeckoPreference
import org.mozilla.geckoview.GeckoResult

/** Values from the supplied Firefox 158 / Windows 10 browser report.
 * Preferences cover requests, frames and workers; desktop_identity.js covers
 * window-only values for which GeckoView has no native override.
 */
object FirefoxDesktopIdentity {
    const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:158.0) " +
        "Gecko/20100101 Firefox/158.0"
    const val WEBGL_VENDOR = "Google Inc. (AMD)"
    const val WEBGL_RENDERER =
        "ANGLE (AMD, Radeon R9 200 Series Direct3D11 vs_5_0 ps_5_0), or similar"

    fun apply(): GeckoResult<Map<String, Boolean>> {
        val branch = GeckoPreferenceController.PREF_BRANCH_USER
        return GeckoPreferenceController.setGeckoPrefs(listOf(
            SetGeckoPreference.setStringPref("general.useragent.override", USER_AGENT, branch),
            SetGeckoPreference.setStringPref("general.platform.override", "Win32", branch),
            SetGeckoPreference.setStringPref("general.oscpu.override", "Windows NT 10.0; Win64; x64", branch),
            SetGeckoPreference.setStringPref("general.appversion.override", "5.0 (Windows)", branch),
            SetGeckoPreference.setStringPref("intl.accept_languages", "en-US, en", branch),
            SetGeckoPreference.setStringPref("webgl.override-unmasked-vendor", WEBGL_VENDOR, branch),
            SetGeckoPreference.setStringPref("webgl.override-unmasked-renderer", WEBGL_RENDERER, branch),
            // The supplied renderer is already Firefox's sanitized Windows
            // value. Android's sanitizer otherwise replaces it with Generic Renderer.
            SetGeckoPreference.setBoolPref("webgl.sanitize-unmasked-renderer", false, branch),
            SetGeckoPreference.setBoolPref("privacy.donottrackheader.enabled", false, branch),
            SetGeckoPreference.setBoolPref("media.peerconnection.enabled", false, branch),
            // A desktop without a touchscreen has no TouchEvent or ontouch*
            // handlers; TikTok sends phones to its app. Taps still arrive as
            // pointer and mouse events, and APZ still scrolls.
            SetGeckoPreference.setIntPref("dom.w3c_touch_events.enabled", 0, branch),
            SetGeckoPreference.setBoolPref("dom.w3c_touch_events.legacy_apis.enabled", false, branch),
        )).map { applied ->
            check(applied != null && applied.values.all { it }) {
                "Firefox desktop preferences rejected: $applied"
            }
            applied
        }
    }
}
