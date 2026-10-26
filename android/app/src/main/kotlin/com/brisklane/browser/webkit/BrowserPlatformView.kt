package com.brisklane.browser.webkit

import android.annotation.SuppressLint
import android.content.Context
import android.content.pm.ApplicationInfo
import android.graphics.Bitmap
import android.net.http.SslError
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.MotionEvent
import android.view.View
import android.webkit.PermissionRequest
import android.webkit.RenderProcessGoneDetail
import android.webkit.SslErrorHandler
import android.webkit.WebChromeClient
import android.webkit.WebResourceError
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import androidx.webkit.WebViewCompat
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.platform.PlatformView
import org.json.JSONArray
import org.json.JSONObject
import org.json.JSONTokener
import java.io.ByteArrayInputStream
import java.util.UUID

class BrowserPlatformView(
    context: Context,
    messenger: BinaryMessenger,
    viewId: Int,
    args: Map<String, Any?>,
) : PlatformView, MethodChannel.MethodCallHandler {
    companion object {
        private const val TAG = "BrowserPlatformView"
        private const val bridgeName = "browser_bridge"
        // The only pages whose scripts report back through the bridge.
        private val bridgeOrigins = setOf("https://tiktok.com", "https://*.tiktok.com")
        @Volatile var active: BrowserPlatformView? = null
            private set

        // Adds callHandler to the injected bridge and keeps it out of
        // enumeration; replies come back on the same frame's bridge.
        private val bridgeScript = """
            (() => {
              const bridge = window.$bridgeName;
              if (!bridge || bridge.callHandler) return;
              try { Object.defineProperty(window, '$bridgeName', {enumerable: false}); } catch (_) {}
              const pending = new Map();
              let next = 0;
              const normalize = value => {
                if (value === undefined) return null;
                try { return JSON.parse(JSON.stringify(value)); }
                catch (_) { return String(value); }
              };
              bridge.addEventListener('message', event => {
                let message;
                try { message = JSON.parse(event.data); } catch (_) { return; }
                const entry = pending.get(message?.id);
                if (!entry) return;
                pending.delete(message.id);
                message.ok ? entry.resolve(message.value) : entry.reject(new Error(message.error));
              });
              Object.defineProperty(bridge, 'callHandler', {
                value(name, ...args) {
                  const id = String(++next);
                  return new Promise((resolve, reject) => {
                    pending.set(id, {resolve, reject});
                    bridge.postMessage(JSON.stringify({type: 'handler', id, name: String(name), args: normalize(args)}));
                  });
                },
              });
            })();
        """.trimIndent()

        // Emulators only: Android 9 images decode HEVC with Codec2, which
        // crashes the app process (WebView decodes in-process) as soon as
        // TikTok plays a video. Reporting HEVC as unsupported makes TikTok
        // serve H.264. Real phones keep the native answers.
        private val isEmulator = Build.HARDWARE in setOf("ranchu", "goldfish")
        private val hevcProbe = Regex("/webapp-desktop/playback\\d*\\.mp4$")
        private val noHevcScript = """
            (() => {
              const hevc = /\b(hev1|hvc1|hevc|h265)\b/i;
              const wrap = (target, key, apply) => {
                const d = target && Object.getOwnPropertyDescriptor(target, key);
                if (!d || typeof d.value !== 'function') return;
                d.value = new Proxy(d.value, {apply});
                Object.defineProperty(target, key, d);
              };
              wrap(window.MediaSource, 'isTypeSupported', (f, self, args) =>
                hevc.test(String(args[0])) ? false : Reflect.apply(f, self, args));
              wrap(window.HTMLMediaElement?.prototype, 'canPlayType', (f, self, args) =>
                hevc.test(String(args[0])) ? '' : Reflect.apply(f, self, args));
              wrap(window.MediaCapabilities?.prototype, 'decodingInfo', (f, self, args) =>
                hevc.test(String(args[0]?.video?.contentType))
                  ? Promise.resolve({supported: false, smooth: false, powerEfficient: false})
                  : Reflect.apply(f, self, args));
              wrap(window.VideoDecoder, 'isConfigSupported', (f, self, args) =>
                hevc.test(String(args[0]?.codec))
                  ? Promise.resolve({supported: false, config: args[0]})
                  : Reflect.apply(f, self, args));
            })();
        """.trimIndent()
    }

    private val channel = MethodChannel(messenger, "test_tiktok/browser_view_$viewId")
    @SuppressLint("ViewConstructor")
    private val webView = object : WebView(context) {
        // Zoom is locked so recorded tap points stay aligned: drop the second
        // finger of a pinch. Taps and Accessibility gestures use one pointer.
        override fun dispatchTouchEvent(event: MotionEvent): Boolean =
            event.pointerCount > 1 || super.dispatchTouchEvent(event)
    }
    private val handler = Handler(Looper.getMainLooper())
    private val initialUrl = (args["initialUrl"] as? String)?.takeIf { it.isNotBlank() }
    // A page script cannot produce this key, so it marks a thrown error.
    private val errorKey = "__browserEvalError_${UUID.randomUUID().toString().replace("-", "")}"
    private val missingFeatures = DesktopChromeIdentity.missingFeatures()
    val profileName = BrowserProfiles.name((args["contextId"] as? String).orEmpty())
    private var viewportLocked = false
    private var mainFrameFailed = false
    private var currentUrl: String? = null
    private var disposed = false

    init {
        active = this
        channel.setMethodCallHandler(this)
        // Credentials are managed by the app. Android's save-password sheet
        // otherwise covers TikTok's verification dialog during automatic login.
        webView.importantForAutofill = View.IMPORTANT_FOR_AUTOFILL_NO_EXCLUDE_DESCENDANTS
        // Debug builds only: chrome://inspect reaches the page for diagnostics.
        if (context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            WebView.setWebContentsDebuggingEnabled(true)
        }
        if (missingFeatures.isEmpty()) configure(args)
        else Log.e(TAG, "WebView lacks $missingFeatures")
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun configure(args: Map<String, Any?>) {
        // The profile must be set before anything else touches the WebView.
        androidx.webkit.ProfileStore.getInstance().getOrCreateProfile(profileName)
        WebViewCompat.setProfile(webView, profileName)
        WebViewCompat.getProfile(webView).cookieManager.setAcceptThirdPartyCookies(webView, true)
        webView.settings.apply {
            javaScriptEnabled = true
            domStorageEnabled = true
            mediaPlaybackRequiresUserGesture = false
            setSupportMultipleWindows(false)
            setGeolocationEnabled(false)
            allowFileAccess = false
            allowContentAccess = false
            useWideViewPort = true
            loadWithOverviewMode = true
            setSupportZoom(false)
            builtInZoomControls = false
            displayZoomControls = false
            textZoom = 100
        }
        DesktopChromeIdentity.configure(webView)
        WebViewCompat.addWebMessageListener(webView, bridgeName, bridgeOrigins) { _, message, _, _, reply ->
            val data = runCatching { JSONObject(message.data ?: "") }.getOrNull() ?: return@addWebMessageListener
            val id = data.optString("id")
            val name = data.optString("name")
            if (data.optString("type") != "handler" || id.isBlank() || name.isBlank()) return@addWebMessageListener
            fun respond(ok: Boolean, value: Any?, error: String?) = reply.postMessage(
                JSONObject().put("id", id).put("ok", ok).put("value", toJson(value)).put("error", error).toString(),
            )
            channel.invokeMethod(
                "javascriptHandler",
                mapOf("name" to name, "args" to toFlutter(data.optJSONArray("args") ?: JSONArray())),
                object : MethodChannel.Result {
                    override fun success(value: Any?) = respond(true, value, null)
                    override fun error(code: String, text: String?, details: Any?) = respond(false, null, text ?: code)
                    override fun notImplemented() = respond(false, null, "Handler not registered")
                },
            )
        }
        WebViewCompat.addDocumentStartJavaScript(webView, bridgeScript, bridgeOrigins)
        if (isEmulator) WebViewCompat.addDocumentStartJavaScript(webView, noHevcScript, setOf("*"))
        // The configuration's time zone and WebRTC scripts, in every frame
        // before page scripts run.
        (args["initialScripts"] as? List<*>)?.filterIsInstance<String>()?.forEach { source ->
            WebViewCompat.addDocumentStartJavaScript(webView, source, setOf("*"))
        }
        webView.webViewClient = Client()
        webView.webChromeClient = ChromeClient()
    }

    private inner class Client : WebViewClient() {
        override fun onPageStarted(view: WebView, url: String, favicon: Bitmap?) {
            Log.d(TAG, "pageStart $url")
            mainFrameFailed = false
            currentUrl = url
            emit("loadStart", mapOf("url" to url))
        }

        // success is false when the load failed or a newer navigation
        // replaced it; real failures also arrive as loadError.
        override fun onPageFinished(view: WebView, url: String) {
            Log.d(TAG, "pageStop success=${!mainFrameFailed} $url")
            emit("loadStop", mapOf("url" to url, "success" to !mainFrameFailed))
        }

        override fun doUpdateVisitedHistory(view: WebView, url: String, isReload: Boolean) {
            currentUrl = url
            emit("location", mapOf("url" to url))
        }

        // TikTok probes HEVC by playing this clip; on emulators that decode
        // crashes the app (see noHevcScript), so the probe fails instead.
        override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? =
            if (isEmulator && hevcProbe.containsMatchIn(request.url.path.orEmpty())) {
                WebResourceResponse("video/mp4", null, 404, "Not Found", emptyMap(), ByteArrayInputStream(ByteArray(0)))
            } else null

        // App links (snssdk://, intent://) would only end in an error page.
        override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest): Boolean =
            request.url.scheme !in listOf("http", "https", "about", "data", "blob")

        override fun onReceivedError(view: WebView, request: WebResourceRequest, error: WebResourceError) {
            if (!request.isForMainFrame) return
            mainFrameFailed = true
            val description = error.description?.toString().orEmpty()
            Log.w(TAG, "loadError code=${error.errorCode} $description ${request.url}")
            if (description.contains("ERR_ABORTED")) return
            emit("loadError", mapOf(
                "url" to request.url.toString(),
                "code" to error.errorCode,
                "errorType" to errorType(error.errorCode),
                "description" to description,
            ))
        }

        override fun onReceivedSslError(view: WebView, handler: SslErrorHandler, error: SslError) {
            handler.cancel()
            if (error.url != currentUrl) return
            mainFrameFailed = true
            emit("loadError", mapOf(
                "url" to error.url,
                "code" to error.primaryError,
                "errorType" to "failedSslHandshake",
            ))
        }

        // The WebView cannot be reused after its renderer died; keep the app
        // alive and let the page's error view offer a retry.
        override fun onRenderProcessGone(view: WebView, detail: RenderProcessGoneDetail): Boolean {
            Log.e(TAG, "renderer gone crashed=${detail.didCrash()}")
            emit("loadError", mapOf(
                "url" to currentUrl,
                "code" to -1,
                "errorType" to "other",
                "description" to "WebView renderer stopped",
            ))
            return true
        }
    }

    private inner class ChromeClient : WebChromeClient() {
        override fun onProgressChanged(view: WebView, progress: Int) {
            emit("progress", mapOf("progress" to progress))
        }

        // Camera, microphone and other web permissions stay denied.
        override fun onPermissionRequest(request: PermissionRequest) = request.deny()

        // WebView otherwise draws a grey play icon over every video until it
        // has a frame; browsers show nothing.
        override fun getDefaultVideoPoster(): Bitmap =
            Bitmap.createBitmap(1, 1, Bitmap.Config.ARGB_8888)
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> {
                if (missingFeatures.isNotEmpty()) emit("loadError", mapOf(
                    "url" to initialUrl,
                    "code" to -1,
                    "errorType" to "unsupportedWebView",
                    "description" to "Android System WebView quá cũ (thiếu $missingFeatures). Hãy cập nhật Android System WebView hoặc Chrome.",
                ))
                else initialUrl?.let(::load)
                result.success(null)
            }
            "loadUrl" -> {
                val url = call.argument<String>("url")
                if (url.isNullOrBlank()) result.error("invalid_url", "URL is empty", null)
                else { load(url); result.success(null) }
            }
            "reload" -> { webView.reload(); result.success(null) }
            "stop" -> { webView.stopLoading(); result.success(null) }
            "goBack" -> { if (webView.canGoBack()) webView.goBack(); result.success(null) }
            "goForward" -> { if (webView.canGoForward()) webView.goForward(); result.success(null) }
            "getUrl" -> result.success(webView.url ?: currentUrl)
            "evaluateJavascript" -> {
                val source = call.argument<String>("source")
                if (source == null) result.error("invalid_script", "JavaScript source is missing", null)
                else evaluate(source, (call.argument<Number>("timeoutMs")?.toLong() ?: 30_000L).coerceIn(1L, 120_000L)) { value, error ->
                    if (error == null) result.success(value)
                    else result.error("javascript_error", error, null)
                }
            }
            else -> result.notImplemented()
        }
    }

    /** Navigates once the view has its width, so the viewport scale is right. */
    private fun load(url: String) {
        if (disposed || missingFeatures.isNotEmpty()) return
        if (webView.width == 0) {
            webView.addOnLayoutChangeListener(object : View.OnLayoutChangeListener {
                override fun onLayoutChange(v: View, l: Int, t: Int, r: Int, b: Int, ol: Int, ot: Int, or: Int, ob: Int) {
                    if (v.width == 0) return
                    v.removeOnLayoutChangeListener(this)
                    load(url)
                }
            })
            return
        }
        if (!viewportLocked) {
            viewportLocked = true
            DesktopChromeIdentity.lockViewport(webView)
        }
        webView.loadUrl(url)
    }

    fun evaluateNative(source: String, callback: (Any?, String?) -> Unit) =
        evaluate(source, 30_000L, callback)

    /**
     * Runs [source] in the top document's page world and returns its
     * completion value. evaluateJavascript is not subject to the page's CSP,
     * unlike eval(), which TikTok's report-only policy would report. Promises
     * are not awaited.
     */
    private fun evaluate(source: String, timeoutMs: Long, callback: (Any?, String?) -> Unit) {
        if (disposed) return callback(null, "WebView was disposed")
        var finished = false
        val timeout = Runnable {
            if (finished) return@Runnable
            finished = true
            callback(null, "The page did not respond before the JavaScript timeout")
        }
        handler.postDelayed(timeout, timeoutMs)
        // A try statement completes with its block's value, so statements
        // and expressions both return what the source evaluates to.
        val script = "try {\n$source\n} catch (error) { ({${JSONObject.quote(errorKey)}: String(error)}) }"
        webView.evaluateJavascript(script) { raw ->
            if (finished) return@evaluateJavascript
            finished = true
            handler.removeCallbacks(timeout)
            val value = toFlutter(raw?.let { runCatching { JSONTokener(it).nextValue() }.getOrNull() })
            if (value is Map<*, *> && value.size == 1 && value.containsKey(errorKey)) {
                callback(null, value[errorKey]?.toString())
            } else callback(value, null)
        }
    }

    fun clearCache() = webView.clearCache(true)

    /** The Dart BrowserWebResourceErrorType name for a WebView load error. */
    private fun errorType(code: Int): String = when (code) {
        WebViewClient.ERROR_TIMEOUT -> "timeout"
        WebViewClient.ERROR_HOST_LOOKUP -> "hostLookup"
        WebViewClient.ERROR_CONNECT -> "cannotConnectToHost"
        WebViewClient.ERROR_IO -> "networkConnectionLost"
        WebViewClient.ERROR_PROXY_AUTHENTICATION -> "proxyAuthentication"
        WebViewClient.ERROR_FAILED_SSL_HANDSHAKE -> "failedSslHandshake"
        else -> "other"
    }

    private fun emit(type: String, data: Map<String, Any?> = emptyMap()) {
        if (!disposed) channel.invokeMethod("event", mapOf("type" to type) + data)
    }

    override fun getView(): View = webView

    override fun dispose() {
        disposed = true
        channel.setMethodCallHandler(null)
        handler.removeCallbacksAndMessages(null)
        webView.stopLoading()
        webView.destroy()
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
