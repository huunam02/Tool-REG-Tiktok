package com.tool.tiktok

import android.view.View
import android.view.ViewGroup
import android.view.inputmethod.EditorInfo
import android.webkit.WebView
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/comment_input")
            .setMethodCallHandler { call, result ->
                if (call.method != "paste") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val webView = findWebView(window.decorView)
                if (webView == null || !webView.hasFocus()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                webView.evaluateJavascript("""
                    (() => {
                      if (document.hidden || window.__flutterAutoWatch?.getStatus?.().commentStage !== 'pasting') return false;
                      const e = document.activeElement;
                      return !!e && !!e.closest('[data-e2e="comment-text"], [data-e2e="comment-input"]') &&
                        (e.isContentEditable || e.tagName === 'TEXTAREA');
                    })()
                """.trimIndent()) { editable ->
                    if (editable != "true") {
                        result.success(false)
                    } else {
                        val connection = webView.onCreateInputConnection(EditorInfo())
                        result.success(connection?.performContextMenuAction(android.R.id.paste) == true)
                    }
                }
            }
    }

    private fun findWebView(view: View): WebView? {
        if (view is WebView) return view
        if (view is ViewGroup) {
            for (index in 0 until view.childCount) {
                findWebView(view.getChildAt(index))?.let { return it }
            }
        }
        return null
    }
}
