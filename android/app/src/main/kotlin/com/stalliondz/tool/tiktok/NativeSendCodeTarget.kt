package com.stalliondz.tool.tiktok

import android.graphics.Rect
import android.webkit.WebView
import org.json.JSONObject

object NativeSendCodeTarget {
    fun read(webView: WebView, attempt: Int, context: String, action: String,
             complete: (Map<String, Double>?) -> Unit) {
        val stateName = when (context) {
            "signup" -> "__flutterAutoSignup"
            "login" -> "__flutterAutoLogin"
            else -> { complete(null); return }
        }
        val targetMethod = when {
            action == "send-code" -> "getSendCodeTarget"
            action == "select-verification-email" && context == "login" -> "getEmailVerificationTarget"
            action == "submit-password" && context == "signup" -> "getPasswordSubmitTarget"
            action == "skip-username" && context == "signup" -> "getUsernameSkipTarget"
            action == "continue-password" && context == "login" -> "getPasswordContinueTarget"
            action == "continue-otp" && context == "login" -> "getOtpContinueTarget"
            else -> { complete(null); return }
        }
        if (!ready(webView)) {
            complete(null)
            return
        }
        val script = """
            (() => {
              if (location.origin !== 'https://www.tiktok.com' || document.hidden) return null;
              return window.$stateName?.$targetMethod?.($attempt) ?? null;
            })()
        """.trimIndent()
        webView.evaluateJavascript(script) { raw ->
            if (!ready(webView)) {
                complete(null)
                return@evaluateJavascript
            }
            val point = try {
                val target = JSONObject(raw)
                val location = IntArray(2)
                webView.getLocationOnScreen(location)
                val visible = Rect()
                if (!webView.getLocalVisibleRect(visible)) null else {
                    // getLocalVisibleRect includes this View's native scroll.
                    // DOM coordinates already describe the visible viewport.
                    visible.offset(-webView.scrollX, -webView.scrollY)
                    toScreen(target, location[0], location[1], webView.width, webView.height, visible)
                }
            } catch (_: Exception) {
                null
            }
            complete(point)
        }
    }

    // Both getLocationOnScreen and Accessibility screenBounds use physical
    // screen pixels. viewportWidth includes the current desktop/pinch zoom;
    // multiplying CSS coordinates by devicePixelRatio alone would be wrong.
    fun toScreen(target: JSONObject, left: Int, top: Int, width: Int, height: Int,
                 visible: Rect): Map<String, Double>? {
        val x = target.optDouble("x", Double.NaN)
        val y = target.optDouble("y", Double.NaN)
        val viewportWidth = target.optDouble("viewportWidth", Double.NaN)
        val viewportHeight = target.optDouble("viewportHeight", Double.NaN)
        if (!listOf(x, y, viewportWidth, viewportHeight).all { it.isFinite() } ||
            width <= 0 || height <= 0 || viewportWidth <= 0 || viewportHeight <= 0 ||
            x < 0 || y < 0 || x >= viewportWidth || y >= viewportHeight) return null
        val scale = width / viewportWidth
        val localX = x * scale
        val localY = y * scale
        if (localX < visible.left || localX >= visible.right ||
            localY < visible.top || localY >= visible.bottom ||
            localX >= width || localY >= height) return null
        return mapOf("x" to left + localX, "y" to top + localY)
    }

    private fun ready(webView: WebView) = webView.isShown &&
        webView.isAttachedToWindow && webView.hasWindowFocus() &&
        webView.width > 0 && webView.height > 0
}
