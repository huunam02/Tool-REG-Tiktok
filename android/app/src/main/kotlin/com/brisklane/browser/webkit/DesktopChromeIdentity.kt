package com.brisklane.browser.webkit

import android.content.Context
import android.util.Log
import android.webkit.WebSettings
import android.webkit.WebView
import androidx.webkit.CustomHeader
import androidx.webkit.UserAgentMetadata
import androidx.webkit.WebSettingsCompat
import androidx.webkit.WebViewCompat
import androidx.webkit.WebViewFeature

/**
 * The only browser identity: Chrome for Android with "Desktop site" on, at
 * the installed System WebView's Chromium version. User-Agent and Client
 * Hints agree before the first navigation. navigator.platform stays native
 * ("Linux aarch64" on a 64-bit phone, as in Chrome): WebView does not derive
 * it from the overridden UA, and a patched getter would differ in frames.
 */
object DesktopChromeIdentity {
    private const val TAG = "BrowserIdentity"
    private const val layoutWidth = 980

    // Desktop site ignores mobile viewport directives: keep a 980 CSS-pixel
    // layout at one fixed scale, even when the page replaces its viewport,
    // so recorded tap points stay aligned.
    private val viewportScript = """
        (() => {
            if (window.top !== window) return;
            const content = '__VIEWPORT_CONTENT__';
            const normalize = (element) => {
                if (element.tagName === 'META' &&
                    (element.getAttribute('name') || '').toLowerCase() === 'viewport' &&
                    element.getAttribute('content') !== content) {
                    element.setAttribute('content', content);
                }
            };
            const scan = (node) => {
                if (node.nodeType !== 1) return;
                normalize(node);
                node.querySelectorAll('meta').forEach(normalize);
            };
            const ensureViewport = () => {
                if (document.head && !document.querySelector('meta[name="viewport" i]')) {
                    const viewport = document.createElement('meta');
                    viewport.name = 'viewport';
                    viewport.content = content;
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

    /** The features [configure] and the browser view cannot work without. */
    val requiredFeatures = listOf(
        WebViewFeature.DOCUMENT_START_SCRIPT,
        WebViewFeature.USER_AGENT_METADATA,
        WebViewFeature.WEB_MESSAGE_LISTENER,
        WebViewFeature.MULTI_PROFILE,
    )

    fun missingFeatures(): List<String> =
        requiredFeatures.filterNot(WebViewFeature::isFeatureSupported)

    private fun chromiumVersion(context: Context): String =
        Regex("Chrome/(\\d+(?:\\.\\d+){3})").find(WebSettings.getDefaultUserAgent(context))
            ?.groupValues?.get(1)
            ?: error("Không đọc được phiên bản Chromium của WebView.")

    /** What the page and the app's own requests announce. */
    fun userAgent(context: Context): String =
        "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 " +
            "(KHTML, like Gecko) Chrome/${chromiumVersion(context).substringBefore('.')}.0.0.0 Safari/537.36"

    /** Call on the UI thread after the WebView's profile is set, before navigation. */
    fun configure(webView: WebView) {
        val version = chromiumVersion(webView.context)
        val major = version.substringBefore('.')
        val settings = webView.settings
        maskPackageName(webView)
        settings.userAgentString = userAgent(webView.context)
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
        val metadata = UserAgentMetadata.Builder(defaults)
            .setBrandVersionList(brands)
            .setFullVersion(version)
            .setPlatform("Linux")
            .setPlatformVersion("")
            .setArchitecture("x86")
            .setBitness(64)
            .setModel("")
            .setMobile(false)
            .setWow64(false)
        if (WebViewFeature.isFeatureSupported(WebViewFeature.USER_AGENT_METADATA_FORM_FACTORS)) {
            metadata.setFormFactors(listOf(UserAgentMetadata.FORM_FACTOR_DESKTOP))
        }
        WebSettingsCompat.setUserAgentMetadata(settings, metadata.build())
    }

    /**
     * Fixes the page at 980 CSS pixels across the laid-out view. Call once
     * the view has its width, before the first navigation.
     */
    fun lockViewport(webView: WebView) {
        val widthDp = webView.width / webView.resources.displayMetrics.density
        val scale = widthDp / layoutWidth
        val content = "width=$layoutWidth, initial-scale=$scale, minimum-scale=$scale, " +
            "maximum-scale=$scale, user-scalable=no"
        WebViewCompat.addDocumentStartJavaScript(
            webView,
            viewportScript.replace("__VIEWPORT_CONTENT__", content),
            setOf("*"),
        )
    }

    /**
     * Hides the embedding app's package from X-Requested-With: removed where
     * the WebView allows it, otherwise replaced on the profile. Chromium
     * excludes CORS preflight from custom headers, so OPTIONS can still
     * expose the package.
     */
    private fun maskPackageName(webView: WebView) {
        val outcome = when {
            WebViewFeature.isFeatureSupported(WebViewFeature.REQUESTED_WITH_HEADER_ALLOW_LIST) -> {
                WebSettingsCompat.setRequestedWithHeaderOriginAllowList(webView.settings, emptySet())
                "removed"
            }
            WebViewFeature.isFeatureSupported(WebViewFeature.CUSTOM_REQUEST_HEADERS) -> {
                // Adding the same name/value again merges rules instead of duplicating it.
                WebViewCompat.getProfile(webView).addCustomHeader(
                    CustomHeader("X-Requested-With", "XMLHttpRequest", setOf("*")),
                )
                "replaced with XMLHttpRequest (CORS preflight may still send the package)"
            }
            else -> "unavailable; the package may still be sent"
        }
        Log.i(TAG, "X-Requested-With: $outcome")
    }
}
