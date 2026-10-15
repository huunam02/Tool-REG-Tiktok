package com.stalliondz.tool.tiktok

import android.graphics.Rect
import android.view.View
import android.webkit.WebView
import org.json.JSONObject
import java.util.WeakHashMap

object NativeSendCodeTarget {
    private data class Geometry(
        val left: Int, val top: Int, val width: Int, val height: Int,
        val frame: List<Float>, val windowFrame: Rect, val visible: Rect
    )

    private class GeometryCache {
        var geometry: Geometry? = null
    }

    // Weak keys release the cache when the WebView is disposed. No view is
    // retained by its cache entry, and all access runs on Android's UI thread.
    private val geometryCaches = WeakHashMap<WebView, GeometryCache>()

    private fun frameOf(view: View): List<Float> {
        // Translations/zoom can change without a layout event. Compare cheap
        // view properties up the hierarchy before reusing physical geometry.
        val frame = ArrayList<Float>()
        var current: View? = view
        while (current != null) {
            frame.addAll(listOf(current.left.toFloat(), current.top.toFloat(),
                current.width.toFloat(), current.height.toFloat(),
                current.scrollX.toFloat(), current.scrollY.toFloat(),
                current.translationX, current.translationY,
                current.scaleX, current.scaleY, current.rotation))
            current = current.parent as? View
        }
        return frame
    }

    private fun geometryFor(view: WebView): Geometry? {
        val cache = geometryCaches.getOrPut(view) {
            GeometryCache().also { entry ->
                view.addOnAttachStateChangeListener(object : View.OnAttachStateChangeListener {
                    override fun onViewAttachedToWindow(v: View) { entry.geometry = null }
                    override fun onViewDetachedFromWindow(v: View) { entry.geometry = null }
                })
            }
        }
        val frame = frameOf(view)
        // Window clipping detects IME changes without throwing away geometry
        // just because Android reports another layout for the same modal.
        val windowFrame = Rect()
        view.getWindowVisibleDisplayFrame(windowFrame)
        cache.geometry?.let {
            if (it.frame == frame && it.windowFrame == windowFrame) return it
        }
        val location = IntArray(2)
        view.getLocationOnScreen(location)
        val visible = Rect()
        if (!view.getLocalVisibleRect(visible)) return null
        // DOM coordinates already include scrolling inside the document.
        visible.offset(-view.scrollX, -view.scrollY)
        return Geometry(location[0], location[1], view.width, view.height,
            frame, windowFrame, visible).also { cache.geometry = it }
    }

    fun read(webView: WebView, attempt: Int, context: String, action: String,
             complete: (Map<String, Double>?) -> Unit) {
        val stateName = when (context) {
            "signup" -> "__flutterAutoSignup"
            "login" -> "__flutterAutoLogin"
            else -> { complete(null); return }
        }
        val targetMethod = targetMethod(context, action)
        if (targetMethod == null) { complete(null); return }
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
                geometryFor(webView)?.let {
                    toScreen(target, it.left, it.top, it.width, it.height, it.visible)
                }
            } catch (_: Exception) {
                null
            }
            complete(point)
        }
    }

    private fun targetMethod(context: String, action: String): String? = when {
            action == "send-code" && (context == "login" || context == "signup") -> "getSendCodeTarget"
            action == "select-verification-email" && context == "login" -> "getEmailVerificationTarget"
            action == "submit-password" && context == "signup" -> "getPasswordSubmitTarget"
            action == "skip-username" && context == "signup" -> "getUsernameSkipTarget"
            action == "continue-password" && context == "login" -> "getPasswordContinueTarget"
            action == "continue-otp" && context == "login" -> "getOtpContinueTarget"
            else -> null
        }

    fun invalidate(webView: WebView, context: String, action: String,
                   complete: (Boolean) -> Unit) {
        if (targetMethod(context, action) == null) { complete(false); return }
        geometryCaches[webView]?.geometry = null
        val key = JSONObject.quote("$context/$action")
        webView.evaluateJavascript("""
            (() => {
              if (location.origin !== 'https://www.tiktok.com') return false;
              window.__flutterNativeTapTargets?.delete($key);
              return true;
            })()
        """.trimIndent()) { complete(it == "true") }
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
