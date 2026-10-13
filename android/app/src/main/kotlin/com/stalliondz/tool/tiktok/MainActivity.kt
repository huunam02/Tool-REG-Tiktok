package com.stalliondz.tool.tiktok

import android.content.Context
import android.content.res.Configuration
import android.os.Build
import android.os.LocaleList
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import java.util.Locale

class MainActivity: FlutterActivity() {
    private fun englishConfiguration(configuration: Configuration): Configuration {
        Locale.setDefault(Locale.US)
        return Configuration(configuration).apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
                val locales = LocaleList(Locale.US, Locale.ENGLISH)
                LocaleList.setDefault(locales)
                setLocales(locales)
            } else {
                setLocale(Locale.US)
            }
        }
    }

    override fun attachBaseContext(newBase: Context) {
        // Set Chromium's default languages before any WebView is constructed.
        super.attachBaseContext(newBase.createConfigurationContext(
            englishConfiguration(newBase.resources.configuration)
        ))
    }

    override fun onConfigurationChanged(newConfig: Configuration) {
        // Keep English when the device language changes while the app is open.
        super.onConfigurationChanged(englishConfiguration(newConfig))
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/comment_input")
            .setMethodCallHandler { call, result ->
                if (call.method != "paste") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val webView = findWebView(window.decorView)
                if (webView == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val context = call.argument<String>("context") ?: "comment"
                val guardScript = if (context == "signup" || context == "login") {
                    val attempt = call.argument<Int>("attempt")
                    if (attempt == null) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val stateName = if (context == "signup") "__flutterAutoSignup" else "__flutterAutoLogin"
                    "window.$stateName?.canPasteFromClipboard($attempt) === true"
                } else if (context == "comment") {
                    """
                    (() => {
                      if (document.hidden || window.__flutterAutoWatch?.getStatus?.().commentStage !== 'pasting') return false;
                      const e = document.activeElement;
                      return !!e && !!e.closest('[data-e2e="comment-text"], [data-e2e="comment-input"]') &&
                        (e.isContentEditable || e.tagName === 'TEXTAREA');
                    })()
                    """.trimIndent()
                } else {
                    result.success(false)
                    return@setMethodCallHandler
                }
                NativeClipboardPaste.paste(webView, guardScript) { result.success(it) }
            }
    }

    private fun findWebView(view: View): WebView? {
        // The IP checker adds an invisible headless WebView before TikTok.
        // Clipboard actions must target the visible account/comment page.
        if (view.visibility != View.VISIBLE) return null
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findWebView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}
