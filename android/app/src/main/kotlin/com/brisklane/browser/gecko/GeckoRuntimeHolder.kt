package com.brisklane.browser.gecko

import android.content.Context
import android.util.Log
import org.mozilla.geckoview.ContentBlocking
import org.mozilla.geckoview.GeckoRuntime
import org.mozilla.geckoview.GeckoRuntimeSettings
import org.mozilla.geckoview.WebExtension

object GeckoRuntimeHolder {
    private const val extensionUri = "resource://android/assets/gecko_bridge/"
    private const val extensionId = "gecko-bridge@brisklane.com"

    @Volatile private var runtime: GeckoRuntime? = null
    @Volatile private var extension: WebExtension? = null
    private val waiters = mutableListOf<(WebExtension) -> Unit>()

    @Synchronized
    fun runtime(context: Context): GeckoRuntime {
        runtime?.let { return it }
        return GeckoRuntime.create(
            context.applicationContext,
            // Automation taps recorded screen points; any zoom shifts them.
            GeckoRuntimeSettings.Builder()
                .javaScriptEnabled(true)
                .locales(arrayOf("en-US", "en"))
                .displayDensityOverride(1.0f)
                .screenSizeOverride(1536, 864)
                .contentBlocking(ContentBlocking.Settings.Builder()
                    .cookieBehavior(ContentBlocking.CookieBehavior.ACCEPT_ALL)
                    .cookieBehaviorPrivateMode(ContentBlocking.CookieBehavior.ACCEPT_ALL)
                    .build())
                .inputAutoZoomEnabled(false)
                .doubleTapZoomingEnabled(false)
                .forceUserScalableEnabled(false)
                .build(),
        ).also {
            runtime = it
            it.webExtensionController.ensureBuiltIn(extensionUri, extensionId).accept(
                { installed ->
                    if (installed == null) {
                        Log.e("GeckoBridge", "Bundled extension returned no instance")
                        return@accept
                    }
                    val callbacks = synchronized(this) {
                        extension = installed
                        waiters.toList().also { waiters.clear() }
                    }
                    callbacks.forEach { callback -> callback(installed) }
                },
                { error -> Log.e("GeckoBridge", "Cannot install bundled extension", error) },
            )
        }
    }

    fun whenExtensionReady(context: Context, callback: (WebExtension) -> Unit) {
        runtime(context)
        val ready = synchronized(this) {
            extension ?: run {
                waiters += callback
                null
            }
        }
        ready?.let(callback)
    }
}
