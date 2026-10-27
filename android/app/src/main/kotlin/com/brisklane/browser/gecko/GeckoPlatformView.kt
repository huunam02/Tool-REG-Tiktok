package com.brisklane.browser.gecko

import android.content.Context
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
import org.mozilla.geckoview.GeckoResult
import org.mozilla.geckoview.GeckoSession
import org.mozilla.geckoview.GeckoSessionSettings
import org.mozilla.geckoview.GeckoView
import org.mozilla.geckoview.WebExtension
import org.mozilla.geckoview.WebRequestError
import java.util.UUID

class GeckoPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    private val args: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "GeckoPlatformView"
        @Volatile var active: GeckoPlatformView? = null
            private set
    }
    private val channel = MethodChannel(messenger, "test_tiktok/gecko_view_$viewId")
    private val geckoView = object : GeckoView(context) {
        // Zoom is locked so recorded tap points stay aligned: drop the second
        // finger of a pinch. Taps and Accessibility gestures use one pointer.
        override fun dispatchTouchEvent(event: MotionEvent): Boolean =
            event.pointerCount > 1 || super.dispatchTouchEvent(event)
    }
    private val session: GeckoSession
    private val ports = mutableSetOf<WebExtension.Port>()
    private var topPort: WebExtension.Port? = null
    private val handler = Handler(Looper.getMainLooper())
    private val pending = PendingGeckoEvaluations<WebExtension.Port>(
        schedule = { task, delay -> handler.postDelayed(task, delay); Unit },
        cancel = { task -> handler.removeCallbacks(task) },
    )
    private val initialScripts = (args["initialScripts"] as? List<*>)?.mapNotNull { it as? String }.orEmpty()
    private val initialUrl = (args["initialUrl"] as? String)?.takeIf { it.isNotBlank() }
    private lateinit var identityReady: GeckoResult<*>
    private val extensionReady = GeckoResult<Void>()
    // Completes once the page scale fits the first laid-out frame width.
    private val scaleReady = GeckoResult<Void>()
    private var scaledWidth = 0
    private var scaleCompleted = false

    private fun completeScale() {
        if (scaleCompleted) return
        scaleCompleted = true
        scaleReady.complete(null)
    }
    private var currentUrl: String? = null
    private var disposed = false

    init {
        active = this
        channel.setMethodCallHandler(this)
        // Credentials are managed by the app. Android's save-password sheet
        // otherwise covers TikTok's verification dialog during automatic login.
        geckoView.setAutofillEnabled(false)
        geckoView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        val settingsBuilder = GeckoSessionSettings.Builder()
            .contextId((args["contextId"] as? String)?.takeIf { it.isNotBlank() } ?: "default")
            // Desktop layout with the explicit Firefox Windows identity.
            .userAgentMode(GeckoSessionSettings.USER_AGENT_MODE_DESKTOP)
            .userAgentOverride(FirefoxDesktopIdentity.USER_AGENT)
            .viewportMode(GeckoSessionSettings.VIEWPORT_MODE_DESKTOP)
            .allowJavascript(true)
        val settings = settingsBuilder.build()
        session = GeckoSession(settings)
        bindDelegates()
        session.open(GeckoRuntimeHolder.runtime(context))
        identityReady = FirefoxDesktopIdentity.apply()
        geckoView.setSession(session)
        // The frame changes size when signup rotates the app to landscape;
        // the page keeps the desktop's 1920 CSS px width either way.
        geckoView.addOnLayoutChangeListener { view, _, _, _, _, _, _, _, _ ->
            val width = view.width
            if (width <= 0 || width == scaledWidth || disposed) return@addOnLayoutChangeListener
            scaledWidth = width
            FirefoxDesktopIdentity.applyPageScale(width).accept(
                { if (scaledWidth == width) completeScale() },
                { error -> Log.e(TAG, "Page scale not applied", error) },
            )
        }
        GeckoRuntimeHolder.whenExtensionReady(context) { extension ->
            if (!disposed) {
                bindExtension(extension)
                extensionReady.complete(null)
            }
        }
    }

    private fun bindDelegates() {
        session.progressDelegate = object : GeckoSession.ProgressDelegate {
            override fun onPageStart(session: GeckoSession, url: String) {
                Log.d(TAG, "pageStart $url")
                currentUrl = url
                emit("loadStart", mapOf("url" to url))
            }

            override fun onProgressChange(session: GeckoSession, progress: Int) {
                emit("progress", mapOf("progress" to progress))
            }

            // success is also false when a newer navigation (a redirect, a
            // script setting location) replaced this load; real failures
            // arrive through onLoadError below.
            override fun onPageStop(session: GeckoSession, success: Boolean) {
                Log.d(TAG, "pageStop success=$success $currentUrl")
                emit("loadStop", mapOf("url" to currentUrl, "success" to success))
            }
        }
        session.navigationDelegate = object : GeckoSession.NavigationDelegate {
            override fun onLocationChange(
                session: GeckoSession,
                url: String?,
                perms: MutableList<GeckoSession.PermissionDelegate.ContentPermission>,
                hasUserGesture: Boolean,
            ) {
                currentUrl = url
                emit("location", mapOf("url" to url))
            }

            override fun onLoadError(
                session: GeckoSession,
                uri: String?,
                error: WebRequestError,
            ): GeckoResult<String>? {
                Log.w(TAG, "loadError category=${error.category} code=${error.code} $uri")
                emit("loadError", mapOf(
                    "url" to uri,
                    "code" to error.code,
                    "errorType" to errorType(error.code),
                ))
                return null
            }
        }
        session.permissionDelegate = object : GeckoSession.PermissionDelegate {
            // Without a delegate Gecko denies every request, including video
            // autoplay. Allow autoplay like the old WebView; deny the rest.
            override fun onContentPermissionRequest(
                session: GeckoSession,
                perm: GeckoSession.PermissionDelegate.ContentPermission,
            ): GeckoResult<Int> = GeckoResult.fromValue(
                when (perm.permission) {
                    GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_AUDIBLE,
                    GeckoSession.PermissionDelegate.PERMISSION_AUTOPLAY_INAUDIBLE,
                    -> GeckoSession.PermissionDelegate.ContentPermission.VALUE_ALLOW
                    else -> GeckoSession.PermissionDelegate.ContentPermission.VALUE_DENY
                },
            )
        }
    }

    private fun bindExtension(extension: WebExtension) {
        session.webExtensionController.setMessageDelegate(
            extension,
            object : WebExtension.MessageDelegate {
                override fun onConnect(port: WebExtension.Port) {
                    synchronized(ports) { ports += port }
                    if (port.sender.isTopLevel) setTopPort(port)
                    port.setDelegate(object : WebExtension.PortDelegate {
                        override fun onPortMessage(message: Any, source: WebExtension.Port) {
                            handleExtensionMessage(message, source)
                        }

                        override fun onDisconnect(source: WebExtension.Port) {
                            synchronized(ports) { ports -= source }
                            if (topPort === source) topPort = null
                            pending.disconnect(source, "The page document bridge disconnected")
                        }
                    })
                }
            },
            "browser",
        )
    }

    private fun setTopPort(port: WebExtension.Port) {
        val previous = topPort
        topPort = port
        if (previous != null && previous !== port) {
            pending.disconnect(previous, "The page document was replaced")
        }
    }

    private fun handleExtensionMessage(raw: Any, port: WebExtension.Port) {
        val message = raw as? JSONObject ?: return
        when (message.optString("type")) {
            "ready" -> {
                if (message.optBoolean("top")) setTopPort(port)
                // Every document and frame announces itself at document_start;
                // the configuration's time zone and WebRTC scripts follow.
                initialScripts.forEach { source -> postEval(port, source, true, null) }
                emit("javascriptReady", mapOf("top" to message.optBoolean("top")))
            }
            "evalResult" -> {
                val id = message.optString("id")
                if (message.optBoolean("ok")) pending.reply(id, port, toFlutter(message.opt("value")), null)
                else pending.reply(id, port, null, message.optString("error"))
            }
            "handler" -> {
                val id = message.optString("id")
                val name = message.optString("name")
                if (id.isBlank() || name.isBlank()) return
                channel.invokeMethod(
                    "javascriptHandler",
                    mapOf("name" to name, "args" to toFlutter(message.optJSONArray("args") ?: JSONArray())),
                    object : MethodChannel.Result {
                        override fun success(value: Any?) = replyHandler(port, id, true, value, null)
                        override fun error(code: String, text: String?, details: Any?) =
                            replyHandler(port, id, false, null, text ?: code)
                        override fun notImplemented() = replyHandler(port, id, false, null, "Handler not registered")
                    },
                )
            }
        }
    }

    private fun replyHandler(port: WebExtension.Port, id: String, ok: Boolean, value: Any?, error: String?) {
        port.postMessage(JSONObject().put("type", "handlerResult").put("id", id).put("ok", ok)
            .put("value", toJson(value)).put("error", error))
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                // Never load a page before the identity overrides are in place.
                identityReady.accept(
                    {
                        extensionReady.accept {
                            // A detached view (no window, e.g. a headless
                            // test) is never laid out; don't wait for it.
                            if (!geckoView.isAttachedToWindow) completeScale()
                            else geckoView.postDelayed(::completeScale, 3000)
                            scaleReady.accept {
                                initialUrl?.takeUnless { disposed }?.let(session::loadUri)
                            }
                        }
                    },
                    { error -> Log.e(TAG, "Firefox desktop identity not applied", error) },
                )
                result.success(null)
            }
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) result.error("invalid_url", "URL is empty", null)
                else { session.loadUri(url); result.success(null) }
            }
            "reload" -> { session.reload(); result.success(null) }
            "stop" -> { session.stop(); result.success(null) }
            "goBack" -> { session.goBack(); result.success(null) }
            "goForward" -> { session.goForward(); result.success(null) }
            "getUrl" -> result.success(currentUrl)
            "evaluateJavascript" -> {
                val source = call.argument<String>("source")
                if (source == null) result.error("invalid_script", "JavaScript source is missing", null)
                else evaluate(source, call.argument<Boolean>("pageWorld") == true,
                    (call.argument<Number>("timeoutMs")?.toLong() ?: 30_000L).coerceIn(1L, 120_000L)) { value, error ->
                    if (error == null) result.success(value)
                    else result.error("javascript_error", error, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    fun evaluateNative(source: String, callback: (Any?, String?) -> Unit) =
        evaluate(source, false, callback = callback)

    private fun evaluate(
        source: String,
        pageWorld: Boolean,
        timeoutMs: Long = 30_000L,
        callback: (Any?, String?) -> Unit,
    ) {
        val port = topPort
        if (port == null) {
            callback(null, "The top-level document bridge is not ready")
            return
        }
        val id = UUID.randomUUID().toString()
        pending.add(id, port, timeoutMs, callback)
        try {
            postEval(port, source, pageWorld, id)
        } catch (_: Exception) {
            pending.finish(id, null, "The page document bridge is unavailable")
        }
    }

    private fun postEval(port: WebExtension.Port, source: String, pageWorld: Boolean, id: String?) {
        val message = JSONObject().put("type", "eval").put("source", source).put("pageWorld", pageWorld)
        if (id != null) message.put("id", id)
        port.postMessage(message)
    }

    /** The Dart GeckoWebResourceErrorType name for a Gecko load error. */
    private fun errorType(code: Int): String = when (code) {
        WebRequestError.ERROR_NET_TIMEOUT -> "timeout"
        WebRequestError.ERROR_UNKNOWN_HOST -> "hostLookup"
        WebRequestError.ERROR_CONNECTION_REFUSED,
        WebRequestError.ERROR_UNKNOWN_PROXY_HOST,
        WebRequestError.ERROR_PROXY_CONNECTION_REFUSED,
        -> "cannotConnectToHost"
        WebRequestError.ERROR_NET_RESET,
        WebRequestError.ERROR_NET_INTERRUPT,
        WebRequestError.ERROR_OFFLINE,
        -> "networkConnectionLost"
        WebRequestError.ERROR_SECURITY_SSL,
        WebRequestError.ERROR_SECURITY_BAD_CERT,
        -> "failedSslHandshake"
        else -> "other"
    }

    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        channel.invokeMethod("event", mapOf("type" to type) + data)
    }

    override fun getView(): View = geckoView

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        pending.close()
        synchronized(ports) { ports.forEach { it.disconnect() }; ports.clear() }
        geckoView.releaseSession()
        session.close()
        if (active === this) active = null
    }

    private fun toFlutter(value: Any?): Any? = when (value) {
        null, JSONObject.NULL -> null
        is JSONObject -> value.keys().asSequence().associateWith { toFlutter(value.opt(it)) }
        is JSONArray -> (0 until value.length()).map { toFlutter(value.opt(it)) }
        is Boolean, is Number, is String -> value
        else -> value.toString()
    }

    private fun toJson(value: Any?): Any? = when (value) {
        null -> JSONObject.NULL
        is Map<*, *> -> JSONObject().also { json -> value.forEach { (k, v) -> if (k is String) json.put(k, toJson(v)) } }
        is Iterable<*> -> JSONArray().also { json -> value.forEach { json.put(toJson(it)) } }
        is Boolean, is Number, is String, is JSONObject, is JSONArray -> value
        else -> value.toString()
    }
}
