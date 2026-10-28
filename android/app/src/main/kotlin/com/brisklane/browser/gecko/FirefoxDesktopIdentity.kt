package com.brisklane.browser.gecko

import android.content.Context
import org.mozilla.geckoview.GeckoPreferenceController
import org.mozilla.geckoview.GeckoPreferenceController.SetGeckoPreference
import org.mozilla.geckoview.GeckoResult

/** Firefox 158 on Windows 10, maximized on the most common desktop screen
 * (1920 x 1080 at 100% scaling).
 * Preferences cover requests, frames and workers; desktop_identity.js covers
 * window-only values for which GeckoView has no native override.
 */
object FirefoxDesktopIdentity {
    const val USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:158.0) " +
        "Gecko/20100101 Firefox/158.0"

    /** Windows PC GPUs measured with Firefox; ids match Dart's DesktopGpu,
     * renderers match desktop_identity.js, which picks its WebGL limits by
     * the renderer these preferences expose. */
    enum class Gpu(val id: String, val vendor: String, val renderer: String) {
        AMD_R9_200(
            "amd-r9-200",
            "Google Inc. (AMD)",
            "ANGLE (AMD, Radeon R9 200 Series Direct3D11 vs_5_0 ps_5_0), or similar",
        ),
        INTEL_HD_400(
            "intel-hd-400",
            "Google Inc. (Intel)",
            "ANGLE (Intel, Intel(R) HD Graphics 400 Direct3D11 vs_5_0 ps_5_0), or similar",
        ),
        INTEL_HD(
            "intel-hd",
            "Google Inc. (Intel)",
            "ANGLE (Intel, Intel(R) HD Graphics Direct3D11 vs_5_0 ps_5_0), or similar",
        ),
        ;

        companion object {
            fun byId(id: String?): Gpu = entries.firstOrNull { it.id == id } ?: AMD_R9_200
        }
    }

    const val SCREEN_WIDTH = 1920
    const val SCREEN_HEIGHT = 1080

    /** Page width of maximized Firefox: the full screen width, in CSS px. */
    const val VIEWPORT_WIDTH = SCREEN_WIDTH.toFloat()

    fun density(context: Context): Float = context.resources.displayMetrics.let {
        minOf(it.widthPixels, it.heightPixels) / VIEWPORT_WIDTH
    }

    /** Device pixels per CSS px so a frame [widthPixels] wide shows [VIEWPORT_WIDTH]. */
    fun applyPageScale(widthPixels: Int): GeckoResult<Map<String, Boolean>> =
        GeckoPreferenceController.setGeckoPrefs(listOf(
            SetGeckoPreference.setStringPref(
                "layout.css.devPixelsPerPx",
                String.format(java.util.Locale.US, "%.5f", widthPixels / VIEWPORT_WIDTH),
                GeckoPreferenceController.PREF_BRANCH_USER,
            ),
        ))

    /** Preferences are runtime-wide; the one open GeckoView sets its GPU. */
    fun apply(gpu: Gpu = Gpu.AMD_R9_200): GeckoResult<Map<String, Boolean>> {
        val branch = GeckoPreferenceController.PREF_BRANCH_USER
        return GeckoPreferenceController.setGeckoPrefs(listOf(
            SetGeckoPreference.setStringPref("general.useragent.override", USER_AGENT, branch),
            SetGeckoPreference.setStringPref("general.platform.override", "Win32", branch),
            SetGeckoPreference.setStringPref("general.oscpu.override", "Windows NT 10.0; Win64; x64", branch),
            SetGeckoPreference.setStringPref("general.appversion.override", "5.0 (Windows)", branch),
            SetGeckoPreference.setStringPref("intl.accept_languages", "en-US, en", branch),
            SetGeckoPreference.setStringPref("webgl.override-unmasked-vendor", gpu.vendor, branch),
            SetGeckoPreference.setStringPref("webgl.override-unmasked-renderer", gpu.renderer, branch),
            // The supplied renderer is already Firefox's sanitized Windows
            // value. Android's sanitizer otherwise replaces it with Generic Renderer.
            SetGeckoPreference.setBoolPref("webgl.sanitize-unmasked-renderer", false, branch),
            SetGeckoPreference.setBoolPref("privacy.donottrackheader.enabled", false, branch),
            // The reference PC exposes WebRTC. ICE may gather nothing: no host
            // candidates (Local IP) and no STUN/UDP outside a proxy, which
            // would reveal the real public IP behind the app's VPN proxy.
            SetGeckoPreference.setBoolPref("media.peerconnection.enabled", true, branch),
            SetGeckoPreference.setBoolPref("media.peerconnection.ice.no_host", true, branch),
            SetGeckoPreference.setBoolPref("media.peerconnection.ice.default_address_only", true, branch),
            SetGeckoPreference.setBoolPref("media.peerconnection.ice.obfuscate_host_addresses", true, branch),
            SetGeckoPreference.setBoolPref("media.peerconnection.ice.proxy_only", true, branch),
            // APIs desktop Firefox 158 exposes and GeckoView leaves off.
            SetGeckoPreference.setBoolPref("dom.webgpu.enabled", true, branch),
            // Android is blocked by default even when the WebGPU DOM API is on.
            // Let the native Vulkan backend attempt adapter/device creation.
            SetGeckoPreference.setBoolPref("gfx.webgpu.ignore-blocklist", true, branch),
            SetGeckoPreference.setBoolPref("dom.webmidi.enabled", true, branch),
            SetGeckoPreference.setBoolPref("dom.webserial.enabled", true, branch),
            SetGeckoPreference.setBoolPref("dom.media.webcodecs.enabled", true, branch),
            SetGeckoPreference.setBoolPref("dom.media-pip.enabled", true, branch),
            SetGeckoPreference.setBoolPref("dom.documentpip.enabled", true, branch),
            // A PC disk: storage.estimate() reports the 10 GiB per-site cap.
            SetGeckoPreference.setIntPref("dom.quotaManager.temporaryStorage.fixedLimit", 200 * 1024 * 1024, branch),
            // Touch events stay on natively: the OTP long press needs them to
            // open Gecko's Paste menu. desktop_identity.js hides the touch
            // interfaces from pages; this drops document.createTouch*.
            SetGeckoPreference.setIntPref("dom.w3c_touch_events.enabled", 1, branch),
            SetGeckoPreference.setBoolPref("dom.w3c_touch_events.legacy_apis.enabled", false, branch),
            // The reference PC's mouse: pointer/hover media queries report
            // fine + hover (2 | 4), not the Android touchscreen's coarse/none.
            SetGeckoPreference.setIntPref("ui.primaryPointerCapabilities", 6, branch),
            SetGeckoPreference.setIntPref("ui.allPointerCapabilities", 6, branch),
            // Firefox on Windows has no navigator.share.
            SetGeckoPreference.setBoolPref("dom.webshare.enabled", false, branch),
        )).map { applied ->
            check(applied != null && applied.values.all { it }) {
                "Firefox desktop preferences rejected: $applied"
            }
            applied
        }
    }
}
