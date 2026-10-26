package com.brisklane.browser.webkit

import android.webkit.CookieManager
import android.webkit.WebStorage
import androidx.webkit.Profile
import androidx.webkit.ProfileStore
import androidx.webkit.WebViewFeature

/**
 * One WebView profile per configuration: cookies, DOM storage, cache and
 * service workers are partitioned natively by the context ID. UI thread only.
 */
object BrowserProfiles {
    /** Profile names allow only a conservative character set. */
    fun name(contextId: String): String =
        contextId.ifBlank { "default" }.replace(Regex("[^A-Za-z0-9_-]"), "_")

    fun clear(contextId: String, done: () -> Unit) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            wipe(CookieManager.getInstance(), WebStorage.getInstance(), done)
            return
        }
        clearProfile(name(contextId), done)
    }

    fun clearAll(done: () -> Unit) {
        if (!WebViewFeature.isFeatureSupported(WebViewFeature.MULTI_PROFILE)) {
            wipe(CookieManager.getInstance(), WebStorage.getInstance(), done)
            return
        }
        val names = ProfileStore.getInstance().allProfileNames.toMutableList()
        fun next() {
            if (names.isEmpty()) done() else clearProfile(names.removeAt(0), ::next)
        }
        next()
    }

    private fun clearProfile(name: String, done: () -> Unit) {
        val store = ProfileStore.getInstance()
        BrowserPlatformView.active?.takeIf { it.profileName == name }?.clearCache()
        if (name != Profile.DEFAULT_PROFILE_NAME) {
            try {
                // Deleting removes every kind of site data at once; false
                // means there was no such profile. A Profile fetched before
                // the attempt is unusable afterwards (WebView 138 NPEs).
                store.deleteProfile(name)
                return done()
            } catch (_: IllegalStateException) {
                // Still attached to a WebView: clear its data in place.
            }
        }
        val profile = store.getProfile(name) ?: return done()
        wipe(profile.cookieManager, profile.webStorage, done)
    }

    private fun wipe(cookies: CookieManager, storage: WebStorage, done: () -> Unit) {
        storage.deleteAllData()
        cookies.removeAllCookies {
            cookies.flush()
            done()
        }
    }
}
