package com.brisklane.browser;

import android.util.Log;
import android.webkit.WebView;
import androidx.webkit.CustomHeader;
import androidx.webkit.WebViewCompat;
import androidx.webkit.WebViewFeature;
import java.util.Collections;

/** Masks the embedding app's package without intercepting or replaying HTTP requests. */
public final class WebViewHeaderPrivacy {
    private static boolean logged;

    private WebViewHeaderPrivacy() {}

    /** Call on the UI thread before navigation, including for headless WebViews. */
    public static boolean maskPackageName(WebView webView) {
        boolean supported = WebViewFeature.isFeatureSupported(WebViewFeature.CUSTOM_REQUEST_HEADERS)
            && WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE);
        if (supported) {
            // Profile headers cover navigations, subresources and new service workers.
            // Adding the same name/value again merges rules instead of duplicating it.
            // Use a fixed replacement value. Chromium excludes CORS preflight
            // from custom headers, so OPTIONS can still expose the package name.
            // A page's explicitly supplied X-Requested-With takes precedence as well.
            WebViewCompat.getProfile(webView).addCustomHeader(
                new CustomHeader("X-Requested-With", "XMLHttpRequest", Collections.singleton("*")));
        }
        if (!logged) {
            logged = true;
            Log.i("BrowserIdentity", supported
                ? "X-Requested-With: XMLHttpRequest profile default configured; CORS preflight OPTIONS may still send the package"
                : "X-Requested-With: package masking unavailable in this WebView; package may still be sent");
        }
        return supported;
    }
}
