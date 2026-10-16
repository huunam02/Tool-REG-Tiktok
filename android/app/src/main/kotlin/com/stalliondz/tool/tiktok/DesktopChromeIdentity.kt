package com.stalliondz.tool.tiktok

import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/** Configure matching desktop User-Agent and Client Hints before navigation. */
object DesktopChromeIdentity {
    // Chrome's "Desktop site" ignores mobile viewport directives. WebView's
    // desktop UA alone does not, so keep the default 980 CSS-pixel phone layout
    // even when the site inserts/replaces its viewport after navigation.
    private val desktopViewportScript = """
        (() => {
            // Keep the legacy JS platform consistent with the desktop UA and
            // native Client Hints, including documents inside frames.
            Object.defineProperty(Navigator.prototype, 'platform', {
                get: () => 'Linux x86_64', configurable: false
            });
            // Pixel 9 Pro XL hardware profile, also in subframes. Desktop
            // Chrome still advertises Linux/x86 in UA and Client Hints.
            // Device Memory is deliberately capped at 8 GiB by Chromium,
            // including on this 16 GiB phone. Keep real screen/DPR metrics
            // so rendering, media queries and native touch coordinates agree.
            if (__EMULATE_HARDWARE__) for (const [key, value] of Object.entries({
                hardwareConcurrency: 8, deviceMemory: 8
            })) {
                Object.defineProperty(Navigator.prototype, key, {
                    get: () => value, configurable: false
                });
            }
            if (window.top !== window) return;
            const normalize = (element) => {
                if (element.tagName === 'META' &&
                    (element.getAttribute('name') || '').toLowerCase() === 'viewport' &&
                    element.getAttribute('content') !== '__VIEWPORT_CONTENT__') {
                    element.setAttribute('content', '__VIEWPORT_CONTENT__');
                }
            };
            const scan = (node) => {
                if (node.nodeType !== 1) return;
                normalize(node);
                node.querySelectorAll('meta').forEach(normalize);
            };
            const ensureViewport = () => {
                // Pages may omit or remove the tag. Keep a desktop layout
                // without overriding the phone's screen size, DPR or touch.
                if (document.head && !document.querySelector('meta[name="viewport" i]')) {
                    const viewport = document.createElement('meta');
                    viewport.name = 'viewport';
                    viewport.content = '__VIEWPORT_CONTENT__';
                    document.head.prepend(viewport);
                }
            };
            new MutationObserver((records) => {
                for (const record of records) {
                    if (record.type === 'attributes') normalize(record.target);
                    else record.addedNodes.forEach(scan);
                }
                ensureViewport();
            }).observe(document, {
                subtree: true, childList: true, attributes: true,
                attributeFilter: ['name', 'content']
            });
            document.querySelectorAll('meta').forEach(normalize);
            ensureViewport();
        })();
    """.trimIndent()

    @JvmOverloads
    fun configure(webView: WebView, requestedAgent: String? = null,
                  requestedFullVersion: String? = null,
                  emulateHardware: Boolean = true,
                  fixedSignupViewport: Boolean = false): String {
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
        val requestedMajor = requestedAgent?.let {
            Regex("Chrome/(\\d+)\\.").find(it)?.groupValues?.get(1)
                ?: error("User-Agent Chrome desktop không hợp lệ.")
        }
        val version = if (requestedMajor != null) {
            require(requestedFullVersion != null &&
                Regex("\\d+(?:\\.\\d+){3}").matches(requestedFullVersion) &&
                requestedFullVersion.substringBefore('.') == requestedMajor) {
                "Phiên bản Chrome và Client Hints không khớp."
            }
            requestedFullVersion
        } else nativeVersion
        val isMiui = requestedAgent?.contains("XiaoMi/MiuiBrowser/") == true
        val isWindows = !isMiui && requestedAgent?.contains("(Windows NT 10.0; Win64; x64)") == true
        val platform = if (isWindows) "Windows NT 10.0; Win64; x64" else "X11; Linux x86_64"
        val userAgent = if (isMiui) {
            require(version == "135.0.7049.79") { "Phiên bản Chromium của Miui không khớp." }
            "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
                "(KHTML, like Gecko) Chrome/135.0.7049.79 Safari/537.36 " +
                "XiaoMi/MiuiBrowser/14.65.0-gn"
        } else "Mozilla/5.0 ($platform) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/${version.substringBefore('.')}.0.0.0 Safari/537.36"
        require(requestedAgent == null || requestedAgent == userAgent) {
            "User-Agent phải dùng cấu hình Chrome desktop hoặc Miui desktop."
        }
        val major = version.substringBefore('.')
        val settings = webView.settings
        val defaults = WebSettingsCompat.getUserAgentMetadata(settings)
        val brands = if (isMiui) listOf(
            UserAgentMetadata.BrandVersion.Builder()
                .setBrand("Chromium").setMajorVersion(major).setFullVersion(version).build(),
            UserAgentMetadata.BrandVersion.Builder()
                .setBrand("Miui Browser").setMajorVersion("14").setFullVersion("14.65.0").build()
        ) else defaults.brandVersionList.map {
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
        settings.setSupportZoom(!fixedSignupViewport)
        settings.builtInZoomControls = !fixedSignupViewport
        settings.displayZoomControls = false
        settings.textZoom = 100
        webView.setInitialScale(0)
        val metrics = webView.resources.displayMetrics
        val physicalWidth = if (webView.width > 0) webView.width else metrics.widthPixels
        val scale = physicalWidth.toDouble() / metrics.density / 980.0
        val viewportContent = if (fixedSignupViewport)
            "width=980, initial-scale=$scale, minimum-scale=$scale, maximum-scale=$scale, user-scalable=no"
            else "width=980"
        val viewportScript = desktopViewportScript
            .replace("__VIEWPORT_CONTENT__", viewportContent)
            .replace("__EMULATE_HARDWARE__", emulateHardware.toString())
        val identityScript = if (isWindows) viewportScript.replace("Linux x86_64", "Win32")
            else viewportScript
        WebViewCompat.addDocumentStartJavaScript(webView, identityScript, setOf("*"))
        WebSettingsCompat.setUserAgentMetadata(settings,
            UserAgentMetadata.Builder(defaults)
                .setBrandVersionList(brands)
                .setFullVersion(version)
                .setPlatform(if (isWindows) "Windows" else "Linux")
                .setPlatformVersion(if (isWindows) "10.0.0" else "")
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
