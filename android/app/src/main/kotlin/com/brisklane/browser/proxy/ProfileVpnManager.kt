package com.brisklane.browser.proxy

import android.app.Activity
import android.content.Intent
import android.net.VpnService
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.net.URI
import java.util.UUID

class ProfileVpnManager(private val activity: Activity) : MethodChannel.MethodCallHandler {
    companion object { const val REQUEST_VPN = 7104 }
    private val main = Handler(Looper.getMainLooper())
    private val requests = mutableMapOf<String, MethodChannel.Result>()
    private var pendingIntent: Intent? = null
    private var pendingResult: MethodChannel.Result? = null

    init {
        // Reply once the service has applied the request, not when it was sent,
        // so Dart never opens a page on the previous profile's tunnel.
        ProfileVpnService.onRequestDone = { request, error ->
            main.post {
                val result = requests.remove(request) ?: return@post
                if (error == null) result.success(true)
                else result.error("vpn_failed", "Không thể bật proxy SOCKS5: $error", null)
            }
        }
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "start" -> start(call, result)
            // Without a tunnel there is nothing to stop, and starting the service
            // just to stop it fails while the app is in the background.
            "stop" -> if (!ProfileVpnService.hasTunnel) result.success(true)
                else send(Intent(activity, ProfileVpnService::class.java).setAction(ProfileVpnService.ACTION_STOP),
                    result, foreground = false)
            "status" -> result.success(mapOf("running" to (ProfileVpnService.runningProfile != null),
                "profileId" to ProfileVpnService.runningProfile))
            else -> result.notImplemented()
        }
    }

    private fun start(call: MethodCall, result: MethodChannel.Result) {
        val raw = call.argument<String>("proxy")?.trim().orEmpty()
        val profile = call.argument<String>("profileId")?.trim().orEmpty()
        val uri = try { URI(if (raw.contains("://")) raw else "socks5://$raw") }
        catch (_: Exception) { null }
        if (uri == null || uri.scheme.lowercase() !in setOf("socks5", "socks5h") ||
            uri.host.isNullOrBlank() || uri.port !in 1..65535 || profile.isBlank()) {
            result.error("invalid_socks5_proxy", "Proxy phải có dạng socks5://user:pass@host:port", null)
            return
        }
        val userInfo = uri.rawUserInfo?.split(':', limit = 2).orEmpty()
        val service = Intent(activity, ProfileVpnService::class.java)
            .setAction(ProfileVpnService.ACTION_START)
            .putExtra(ProfileVpnService.EXTRA_HOST, uri.host)
            .putExtra(ProfileVpnService.EXTRA_PORT, uri.port)
            .putExtra(ProfileVpnService.EXTRA_USERNAME, userInfo.getOrNull(0)?.decodeUri().orEmpty())
            .putExtra(ProfileVpnService.EXTRA_PASSWORD, userInfo.getOrNull(1)?.decodeUri().orEmpty())
            .putExtra(ProfileVpnService.EXTRA_PROFILE, profile)
            .putExtra(ProfileVpnService.EXTRA_LABEL, call.argument<String>("label")?.trim().orEmpty())
        val permission = VpnService.prepare(activity)
        if (permission == null) {
            send(service, result)
        } else {
            pendingResult?.error("vpn_replaced", "A newer VPN request replaced this request", null)
            pendingIntent = service
            pendingResult = result
            @Suppress("DEPRECATION") activity.startActivityForResult(permission, REQUEST_VPN)
        }
    }

    private fun send(service: Intent, result: MethodChannel.Result, foreground: Boolean = true) {
        val request = UUID.randomUUID().toString()
        requests[request] = result
        service.putExtra(ProfileVpnService.EXTRA_REQUEST, request)
        try {
            if (foreground) ContextCompat.startForegroundService(activity, service)
            else activity.startService(service)
        } catch (error: Exception) {
            requests.remove(request)
            result.error("vpn_failed", "Không thể bật proxy SOCKS5: ${error.message}", null)
        }
    }

    fun onActivityResult(requestCode: Int, resultCode: Int): Boolean {
        if (requestCode != REQUEST_VPN) return false
        val result = pendingResult
        val service = pendingIntent
        pendingResult = null
        pendingIntent = null
        if (resultCode == Activity.RESULT_OK && service != null && result != null) {
            send(service, result)
        } else result?.error("vpn_permission_denied", "Quyền tạo kết nối VPN đã bị từ chối", null)
        return true
    }

    private fun String.decodeUri(): String = java.net.URLDecoder.decode(this, Charsets.UTF_8.name())
}
