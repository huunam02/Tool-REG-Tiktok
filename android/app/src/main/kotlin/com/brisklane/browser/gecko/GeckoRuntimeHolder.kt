package com.brisklane.browser.gecko

import android.content.Context
import android.util.Log
import java.io.File
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

    /** These graphics preferences are read once during Gecko startup. */
    private fun startupConfig(context: Context): String {
        val config = File(context.filesDir, "gecko-desktop-startup.yaml")
        val contents = """
            prefs:
              dom.webgpu.enabled: true
              gfx.webgpu.ignore-blocklist: true
              dom.webgpu.allow-in-parent: true
        """.trimIndent() + "\n"
        if (!config.exists() || config.readText() != contents) config.writeText(contents)
        return config.absolutePath
    }

    @Synchronized
    fun runtime(context: Context): GeckoRuntime {
        runtime?.let { return it }
        return GeckoRuntime.create(
            context.applicationContext,
            // Automation taps recorded screen points; any zoom shifts them.
            GeckoRuntimeSettings.Builder()
                .configFilePath(startupConfig(context))
                .javaScriptEnabled(true)
                .locales(arrayOf("en-US", "en"))
                // The full-width frame shows FirefoxDesktopIdentity.VIEWPORT_WIDTH
                // CSS px, the reference PC's Firefox page width, on any phone.
                .displayDensityOverride(FirefoxDesktopIdentity.density(context))
                // Device pixels; the landscape signup frame runs at 1 dppx, so
                // media queries there read the desktop screen exactly.
                .screenSizeOverride(
                    FirefoxDesktopIdentity.SCREEN_WIDTH,
                    FirefoxDesktopIdentity.SCREEN_HEIGHT,
                )
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
