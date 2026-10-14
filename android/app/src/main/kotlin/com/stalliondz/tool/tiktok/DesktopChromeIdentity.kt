package com.stalliondz.tool.tiktok

import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewFeature

/** Request the same desktop profile as Chrome on an Android phone. */
object DesktopChromeIdentity {
    fun configure(webView: WebView): String {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) {
            "WebView cần hỗ trợ User-Agent Client Hints. Hãy cập nhật Android System WebView."
        }
        check(WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA_FORM_FACTORS)) {
            "WebView cần hỗ trợ Client Hints formFactors. Hãy cập nhật Android System WebView."
        }
        val nativeAgent = WebSettings.getDefaultUserAgent(webView.context)
        val version = Regex("Chrome/(\\d+(?:\\.\\d+){3})").find(nativeAgent)?.groupValues?.get(1)
            ?: error("Không đọc được phiên bản Chromium của WebView.")
        val major = version.substringBefore('.')
        val userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/$major.0.0.0 Safari/537.36"
        val settings = webView.settings
        val defaults = WebSettingsCompat.getUserAgentMetadata(settings)
        val brands = defaults.brandVersionList.map {
            if (it.brand == "Chromium" || it.brand == "Android WebView" || it.brand == "Google Chrome") {
                UserAgentMetadata.BrandVersion.Builder()
                    .setBrand(if (it.brand == "Android WebView") "Google Chrome" else it.brand)
                    .setMajorVersion(major)
                    .setFullVersion(version)
                    .build()
            } else it
        }
        settings.userAgentString = userAgent
        settings.useWideViewPort = true
        settings.loadWithOverviewMode = true
        settings.setSupportZoom(true)
        WebSettingsCompat.setUserAgentMetadata(settings,
            UserAgentMetadata.Builder(defaults)
                .setBrandVersionList(brands)
                .setFullVersion(version)
                .setPlatform("Linux")
                .setPlatformVersion("")
                .setArchitecture("x86")
                .setBitness(64)
                .setModel("")
                .setMobile(false)
                .setFormFactors(listOf(UserAgentMetadata.FORM_FACTOR_DESKTOP))
                .setWow64(false)
                .build())
        return userAgent
    }
}
