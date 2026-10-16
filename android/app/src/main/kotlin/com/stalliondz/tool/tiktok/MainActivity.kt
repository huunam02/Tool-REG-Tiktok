package com.stalliondz.tool.tiktok

import android.view.View
import android.view.ViewGroup
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import android.webkit.WebView
import org.json.JSONObject
import com.pichillilorenzo.flutter_inappwebview_android.InAppWebViewFlutterPlugin
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var signupCalibration: MethodChannel? = null
    private var calibrationReceiver: BroadcastReceiver? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCalibrationIntent(intent)
    }

    private fun handleCalibrationIntent(intent: Intent) {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val action = intent.getStringExtra("signupCalibration") ?: return
        val requestId = intent.getStringExtra("requestId") ?: return
        if (!requestId.matches(Regex("[a-f0-9]{32}"))) return
        if (action !in listOf("snapshot", "select-birthday", "paste-email", "paste-password", "paste-otp", "paste-user-otp", "back", "tap")) return
        signupCalibration?.invokeMethod("calibrate", mapOf(
            "action" to action,
            "userOtp" to intent.getStringExtra("userOtp"),
            "x" to (intent.getStringExtra("x")?.toDoubleOrNull() ?: Double.NaN),
            "y" to (intent.getStringExtra("y")?.toDoubleOrNull() ?: Double.NaN)
        ), object : MethodChannel.Result {
            override fun success(value: Any?) {
                if (value is Map<*, *>) {
                    val document = JSONObject(value)
                    document.put("requestId", requestId)
                    java.io.File(filesDir, "signup-calibration-$requestId.json").writeText(document.toString())
                    android.util.Log.i("SignupCalibration", "Completed: $action")
                }
            }
            override fun error(code: String, message: String?, details: Any?) {
                android.util.Log.i("SignupCalibration", "Failed: $action ($code)")
            }
            override fun notImplemented() { }
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        signupCalibration = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/signup_calibration")
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE != 0) {
            calibrationReceiver = object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) { handleCalibrationIntent(intent) }
            }
            val filter = IntentFilter("$packageName.SIGNUP_CALIBRATE")
            // Shell-only debug control; does not relaunch the Activity or hide IME.
            if (Build.VERSION.SDK_INT >= 33) {
                registerReceiver(calibrationReceiver, filter, "android.permission.DUMP", null, Context.RECEIVER_EXPORTED)
            } else registerReceiver(calibrationReceiver, filter, "android.permission.DUMP", null)
        }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/send_code_target")
            .setMethodCallHandler { call, result ->
                if (call.method != "getTarget" && call.method != "invalidateTarget") {
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
                if (webView == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                if (call.method == "invalidateTarget") {
                    NativeSendCodeTarget.invalidate(webView, context, action) { result.success(it) }
                    return@setMethodCallHandler
                }
                if (attempt == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                NativeSendCodeTarget.read(webView, attempt.toInt(), context, action) { result.success(it) }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/webview_identity")
            .setMethodCallHandler { call, result ->
                if (call.method !in listOf("configure", "configureEngine", "configureSignupViewport")) {
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
                    if (call.method == "configureSignupViewport") {
                        webView.settings.setSupportZoom(false)
                        webView.settings.builtInZoomControls = false
                        webView.settings.displayZoomControls = false
                        webView.settings.textZoom = 100
                        webView.setInitialScale(0)
                        result.success(true)
                        return@setMethodCallHandler
                    }
                    if (call.method == "configureEngine") {
                        result.success(DesktopChromeIdentity.configure(webView, emulateHardware = false,
                            fixedSignupViewport = call.argument<Boolean>("fixedSignupViewport") == true))
                        return@setMethodCallHandler
                    }
                    val userAgent = call.argument<String>("userAgent")
                        ?: error("Thiếu User-Agent Chrome desktop.")
                    val fullVersion = call.argument<String>("chromeFullVersion")
                        ?: error("Thiếu phiên bản Chrome cho Client Hints.")
                    result.success(DesktopChromeIdentity.configure(webView, userAgent, fullVersion,
                        fixedSignupViewport = call.argument<Boolean>("fixedSignupViewport") == true))
                } catch (error: Exception) {
                    result.error("identity_unsupported", error.message, null)
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/comment_input")
            .setMethodCallHandler { call, result ->
                if (call.method != "typeText" && call.method != "paste") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val webView = findWebView(window.decorView)
                if (webView == null) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val text = call.argument<String>("text")
                if (text.isNullOrEmpty()) {
                    result.success(false)
                    return@setMethodCallHandler
                }
                val encodedText = JSONObject.quote(text)
                val context = call.argument<String>("context") ?: "comment"
                val guardScript = if (context == "signup" || context == "login") {
                    val attempt = call.argument<Int>("attempt")
                    val field = call.argument<String>("field")
                    if (attempt == null || field !in listOf("email", "password", "otp")) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    val stateName = if (context == "signup") "__flutterAutoSignup" else "__flutterAutoLogin"
                    "window.$stateName?.canPasteFromClipboard($attempt, ${JSONObject.quote(field)}, $encodedText) === true"
                } else if (context == "comment") {
                    "window.__flutterAutoWatch?.canPasteComment($encodedText) === true"
                } else {
                    result.success(false)
                    return@setMethodCallHandler
                }
                if (call.method == "paste") {
                    if (context !in listOf("signup", "login") ||
                        call.argument<String>("field") != "otp" || !text.matches(Regex("[0-9]{6}"))) {
                        result.success(false)
                        return@setMethodCallHandler
                    }
                    NativeClipboardPaste.paste(webView, guardScript) { result.success(it) }
                } else {
                    NativeKeyboardInput.typeText(webView, text, guardScript) { result.success(it) }
                }
            }
    }

    override fun onDestroy() {
        calibrationReceiver?.let { unregisterReceiver(it) }
        calibrationReceiver = null
        super.onDestroy()
    }

    private fun findWebView(view: View): WebView? {
        // The IP checker adds an invisible headless WebView before TikTok.
        // Keyboard input must target the visible account/comment page.
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
