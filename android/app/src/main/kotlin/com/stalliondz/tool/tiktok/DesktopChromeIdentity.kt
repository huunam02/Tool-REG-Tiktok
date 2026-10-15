package com.stalliondz.tool.tiktok

import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/** Match Chrome Android's desktop profile using the installed Chromium engine. */
object DesktopChromeIdentity {
    // Chrome's "Desktop site" ignores mobile viewport directives. WebView's
    // desktop UA alone does not, so keep the default 980 CSS-pixel phone layout
    // even when the site inserts/replaces its viewport after navigation.
    private val desktopViewportScript = """
        (() => {
            if (window.top !== window) return;
            const normalize = (element) => {
                if (element.tagName === 'META' &&
                    (element.getAttribute('name') || '').toLowerCase() === 'viewport' &&
                    element.getAttribute('content') !== 'width=980') {
                    element.setAttribute('content', 'width=980');
                }
            };
            const scan = (node) => {
                if (node.nodeType !== 1) return;
                normalize(node);
                node.querySelectorAll('meta').forEach(normalize);
            };
            new MutationObserver((records) => {
                for (const record of records) {
                    if (record.type === 'attributes') normalize(record.target);
                    else record.addedNodes.forEach(scan);
                }
            }).observe(document, {
                subtree: true, childList: true, attributes: true,
                attributeFilter: ['name', 'content']
            });
            document.querySelectorAll('meta').forEach(normalize);
        })();
    """.trimIndent()

    fun configure(webView: WebView): String {
        check(WebViewFeature.isFeatureSupported(WebViewFeature.DOCUMENT_START_SCRIPT)) {
            "WebView cần hỗ trợ cấu hình viewport trước khi tải trang. Hãy cập nhật Android System WebView."
        }
        check(WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA)) {
            "WebView cần hỗ trợ User-Agent Client Hints. Hãy cập nhật Android System WebView."
        }
        check(WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA_FORM_FACTORS)) {
            "WebView cần hỗ trợ Client Hints formFactors. Hãy cập nhật Android System WebView."
        }
        val nativeAgent = WebSettings.getDefaultUserAgent(webView.context)
        val nativeVersion = Regex("Chrome/(\\d+(?:\\.\\d+){3})").find(nativeAgent)?.groupValues?.get(1)
            ?: error("Không đọc được phiên bản Chromium của WebView.")
        val userAgent = "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/${nativeVersion.substringBefore('.')}.0.0.0 Safari/537.36"
        val version = nativeVersion
        val major = version.substringBefore('.')
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
        settings.builtInZoomControls = true
        settings.displayZoomControls = false
        settings.textZoom = 100
        webView.setInitialScale(0)
        WebViewCompat.addDocumentStartJavaScript(webView, desktopViewportScript, setOf("*"))
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
