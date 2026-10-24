package com.brisklane.browser

import android.app.ActivityManager
import android.content.Intent
import android.content.pm.ApplicationInfo
import android.content.BroadcastReceiver
import android.content.Context
import android.content.IntentFilter
import android.os.Build
import org.json.JSONObject
import com.brisklane.browser.gecko.GeckoViewFactory
import com.brisklane.browser.gecko.GeckoPlatformView
import com.brisklane.browser.proxy.ProfileVpnManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private var signupCalibration: MethodChannel? = null
    private var calibrationReceiver: BroadcastReceiver? = null
    private var profileVpnManager: ProfileVpnManager? = null

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        handleCalibrationIntent(intent)
    }

    @Deprecated("Deprecated in Android")
    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (profileVpnManager?.onActivityResult(requestCode, resultCode) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    private fun handleCalibrationIntent(intent: Intent) {
        if (applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE == 0) return
        val action = intent.getStringExtra("signupCalibration") ?: return
        val requestId = intent.getStringExtra("requestId") ?: return
        if (!requestId.matches(Regex("[a-f0-9]{32}"))) return
        if (action !in listOf("snapshot", "login-profile", "nurture-profile", "nurture-layout", "nurture-swipe", "nurture-prepare-input", "nurture-release-input", "paste-comment", "submit-comment", "diagnose-web", "select-birthday", "paste-email", "paste-password", "paste-otp", "paste-user-otp", "back", "tap")) return
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
                val document = JSONObject(mapOf("ok" to false, "reason" to "calibration-failed:$code", "requestId" to requestId))
                java.io.File(filesDir, "signup-calibration-$requestId.json").writeText(document.toString())
            }
            override fun notImplemented() { }
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        flutterEngine.platformViewsController.registry.registerViewFactory(
            "test_tiktok/gecko_view",
            GeckoViewFactory(this, flutterEngine.dartExecutor.binaryMessenger),
        )
        profileVpnManager = ProfileVpnManager(this)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/profile_vpn")
            .setMethodCallHandler(profileVpnManager)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/gecko_storage")
            .setMethodCallHandler { call, result ->
                val storage = com.brisklane.browser.gecko.GeckoRuntimeHolder.runtime(this).storageController
                when (call.method) {
                    "clearContext" -> {
                        val contextId = call.argument<String>("contextId")
                        if (contextId.isNullOrBlank()) result.error("invalid_context", "Missing Gecko context ID", null)
                        else { storage.clearDataForSessionContext(contextId); result.success(null) }
                    }
                    "clearAll" -> storage.clearData(org.mozilla.geckoview.StorageController.ClearFlags.ALL)
                        .accept({ result.success(null) }, { result.error("clear_failed", it?.message, null) })
                    else -> result.notImplemented()
                }
            }
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
        // Physical RAM, from which Dart derives the phone's navigator.deviceMemory.
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/device")
            .setMethodCallHandler { call, result ->
                if (call.method != "totalMemory") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val memory = ActivityManager.MemoryInfo()
                (getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager).getMemoryInfo(memory)
                result.success(memory.totalMem)
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
                val gecko = GeckoPlatformView.active
                if (gecko == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                val state = if (context == "signup") "__flutterAutoSignup" else "__flutterAutoLogin"
                val method = sendCodeTargetMethod(context, action)
                if (call.method == "invalidateTarget") {
                    val key = JSONObject.quote("$context/$action")
                    gecko.evaluateNative("window.__flutterNativeTapTargets?.delete($key) === true") { value, _ ->
                        result.success(value == true)
                    }
                    return@setMethodCallHandler
                }
                if (attempt == null || method == null) {
                    result.success(null)
                    return@setMethodCallHandler
                }
                gecko.evaluateNative("window.$state?.$method?.(${attempt.toInt()}) ?? null") { value, _ ->
                    val target = value as? Map<*, *>
                    val x = (target?.get("x") as? Number)?.toDouble()
                    val y = (target?.get("y") as? Number)?.toDouble()
                    val viewportWidth = (target?.get("viewportWidth") as? Number)?.toDouble()
                    val viewportHeight = (target?.get("viewportHeight") as? Number)?.toDouble()
                    val view = gecko.view
                    if (x == null || y == null || viewportWidth == null || viewportHeight == null ||
                        viewportWidth <= 0 || viewportHeight <= 0 || x !in 0.0..<viewportWidth || y !in 0.0..<viewportHeight) {
                        result.success(null)
                    } else {
                        val location = IntArray(2).also(view::getLocationOnScreen)
                        val scale = view.width / viewportWidth
                        result.success(mapOf("x" to location[0] + x * scale, "y" to location[1] + y * scale))
                    }
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "test_tiktok/comment_input")
            .setMethodCallHandler { call, result ->
                if (call.method != "typeText" && call.method != "paste") {
                    result.notImplemented()
                    return@setMethodCallHandler
                }
                val gecko = GeckoPlatformView.active
                if (gecko == null) {
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
                val script = """
                    (() => {
                      if (!($guardScript)) return false;
                      const editor = document.activeElement;
                      if (!editor || !editor.isConnected || editor.disabled || editor.readOnly) return false;
                      const value = $encodedText;
                      const proto = editor instanceof HTMLTextAreaElement ? HTMLTextAreaElement.prototype : HTMLInputElement.prototype;
                      const setter = Object.getOwnPropertyDescriptor(proto, 'value')?.set;
                      if (setter) setter.call(editor, value); else editor.value = value;
                      editor.dispatchEvent(new InputEvent('input', {bubbles: true, inputType: 'insertText', data: value}));
                      editor.dispatchEvent(new Event('change', {bubbles: true}));
                      return editor.value === value;
                    })()
                """.trimIndent()
                gecko.evaluateNative(script) { value, _ -> result.success(value == true) }
            }
    }

    override fun onDestroy() {
        calibrationReceiver?.let { unregisterReceiver(it) }
        calibrationReceiver = null
        profileVpnManager = null
        super.onDestroy()
    }

    private fun sendCodeTargetMethod(context: String, action: String): String? = when {
        action == "send-code" && context in listOf("login", "signup") -> "getSendCodeTarget"
        action == "select-verification-email" && context == "login" -> "getEmailVerificationTarget"
        action == "submit-password" && context == "signup" -> "getPasswordSubmitTarget"
        action == "skip-username" && context == "signup" -> "getUsernameSkipTarget"
        action == "continue-password" && context == "login" -> "getPasswordContinueTarget"
        action == "continue-otp" && context == "login" -> "getOtpContinueTarget"
        else -> null
    }
}
