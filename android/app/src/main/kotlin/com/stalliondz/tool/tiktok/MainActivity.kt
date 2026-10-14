package com.stalliondz.tool.tiktok

import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/send_code_target")
            .setMethodCallHandler { call, result ->
                if (call.method != "getTarget") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val id = call.argument<Number>("id")
                val attempt = call.argument<Number>("attempt")
                val context = call.argument<String>("context") ?: "login"
                val action = call.argument<String>("action") ?: "send-code"
                val root = id?.let {
                    flutterEngine.platformViewsController.getPlatformViewById(it.toInt())
                }
                val webView = root?.let { findWebView(it) }
                if (webView == null || attempt == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                NativeSendCodeTarget.read(webView, attempt.toInt(), context, action) { result.success(it) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/webview_identity")
            .setMethodCallHandler { call, result ->
                if (call.method != "configure") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val id = call.argument<Any>("id")
                val root = if (id is Number) {
                    flutterEngine.platformViewsController.getPlatformViewById(id.toInt())
                } else {
                    val plugin = flutterEngine.plugins.get(InAppWebViewFlutterPlugin::class.java)
                        as? InAppWebViewFlutterPlugin
                    plugin?.headlessInAppWebViewManager?.webViews?.get(id as? String)
                        ?.flutterWebView?.view
                }
                val webView = root?.let { findIdentityWebView(it) }
                if (webView == null) {
                    result.error("identity_view_missing", "Không tìm thấy WebView để cấu hình Chrome desktop.", null)
                    return@setMethodCallHandler
                }
                try {
                    result.success(DesktopChromeIdentity.configure(webView))
                } catch (error: Exception) {
                    result.error("identity_unsupported", error.message, null)
                }
            }
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

    private fun findIdentityWebView(view: View): WebView? {
        // Headless IP probes are invisible but need the same HTTP identity.
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findIdentityWebView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}
