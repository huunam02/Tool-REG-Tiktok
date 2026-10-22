package com.brisklane.browser.proxy

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Intent
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.VpnService
import android.os.Build
import android.os.IBinder
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import androidx.core.app.NotificationCompat
import com.brisklane.browser.MainActivity
import com.brisklane.browser.R
import hev.htproxy.TProxyService
import java.io.File
import java.net.Inet4Address
import java.net.InetAddress
import java.util.concurrent.Executors

class ProfileVpnService : VpnService() {
    companion object {
        const val ACTION_START = "com.brisklane.browser.proxy.START"
        const val ACTION_STOP = "com.brisklane.browser.proxy.STOP"
        const val EXTRA_HOST = "host"
        const val EXTRA_PORT = "port"
        const val EXTRA_USERNAME = "username"
        const val EXTRA_PASSWORD = "password"
        const val EXTRA_PROFILE = "profile"
        const val EXTRA_REQUEST = "request"
        const val EXTRA_LABEL = "label"
        private const val notificationId = 4107
        private const val mapDnsAddress = "198.18.0.2"
        private const val channelId = "profile_proxy"
        private const val startTimeoutMs = 5000L

        @Volatile var runningProfile: String? = null
            private set

        /** Called off the main thread once a request has taken effect; error is null on success. */
        @Volatile var onRequestDone: ((request: String, error: String?) -> Unit)? = null

        // One worker applies requests in order, across service instances, and
        // keeps proxy DNS off the main thread.
        private val executor = Executors.newSingleThreadExecutor()
        @Volatile private var tunnelFd = -1

        /** Whether a tunnel is up; Dart awaits each request, so none is in flight here. */
        val hasTunnel: Boolean get() = tunnelFd >= 0
        private var tunnelOwner: ProfileVpnService? = null
    }

    override fun onBind(intent: Intent?): IBinder? = super.onBind(intent)

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val request = intent?.getStringExtra(EXTRA_REQUEST)
        when (intent?.action) {
            ACTION_START -> {
                // startForegroundService requires this before any slow work.
                val label = intent.getStringExtra(EXTRA_LABEL)?.takeIf { it.isNotBlank() }
                startForeground(notificationId, notification(label ?: intent.getStringExtra(EXTRA_PROFILE).orEmpty()))
                executor.execute { apply(request) { startTunnel(intent) } }
            }
            ACTION_STOP -> executor.execute { apply(request) { stopTunnel() } }
        }
        return START_NOT_STICKY
    }

    private fun apply(request: String?, action: () -> Unit) {
        val error = try {
            action()
            null
        } catch (error: Exception) {
            android.util.Log.e("ProfileVpn", "Cannot apply SOCKS5 tunnel", error)
            stopTunnel()
            error.message ?: error.javaClass.simpleName
        }
        if (request != null) onRequestDone?.invoke(request, error)
    }

    private fun startTunnel(intent: Intent) {
        val host = intent.getStringExtra(EXTRA_HOST)?.trim().orEmpty()
        val port = intent.getIntExtra(EXTRA_PORT, 0)
        val profile = intent.getStringExtra(EXTRA_PROFILE)?.trim().orEmpty()
        require(host.isNotEmpty() && port in 1..65535 && profile.isNotEmpty()) { "Invalid SOCKS5 proxy" }

        val proxyAddress = resolveProxy(host)
        val builder = Builder()
            .setSession("Tool TikTok · $profile")
            .setMtu(1500)
            .addAddress("198.18.0.1", 32)
            // hev's mapdns answers here; see buildConfig.
            .addDnsServer(mapDnsAddress)
            // Capture IPv6 too so it cannot bypass the proxy; the tunnel has no
            // IPv6 upstream, so those connections fail and Gecko uses IPv4.
            .addAddress("fd00:7f3e:2a1c::1", 128)
            .addRoute("::", 0)
            .addAllowedApplication(packageName)
        routesExcluding(proxyAddress.address).forEach { (address, prefix) ->
            builder.addRoute(address, prefix)
        }
        // Establish before closing the previous tunnel: Android moves the routes
        // to the new interface at once, so a switch never falls back to the
        // device network or keeps using the previous profile's proxy.
        val descriptor = builder.establish() ?: throw IllegalStateException("Cannot establish Android VPN")
        closeTunnel()
        val fd = descriptor.detachFd()
        tunnelFd = fd
        tunnelOwner = this

        val config = File(filesDir, "hev-${profile.hashCode().toUInt()}.yml")
        config.writeText(buildConfig(proxyAddress.hostAddress!!, port,
            intent.getStringExtra(EXTRA_USERNAME).orEmpty(),
            intent.getStringExtra(EXTRA_PASSWORD).orEmpty()))
        Thread({ TProxyService.TProxyStartService(config.absolutePath, fd) }, "hev-socks5-$profile").start()
        val deadline = SystemClock.elapsedRealtime() + startTimeoutMs
        while (!TProxyService.TProxyIsRunning()) {
            check(SystemClock.elapsedRealtime() < deadline) { "SOCKS5 tunnel did not start" }
            Thread.sleep(20)
        }
        runningProfile = profile
    }

    /** Resolves on the device network: through our own VPN, mapdns would answer with a fake IP. */
    private fun resolveProxy(host: String): InetAddress {
        val connectivity = getSystemService(ConnectivityManager::class.java)
        @Suppress("DEPRECATION")
        val network = connectivity.allNetworks.firstOrNull { network ->
            connectivity.getNetworkCapabilities(network)?.let {
                !it.hasTransport(NetworkCapabilities.TRANSPORT_VPN) &&
                    it.hasCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET)
            } == true
        }
        val addresses = network?.let { runCatching { it.getAllByName(host) }.getOrNull() }
            ?: InetAddress.getAllByName(host)
        val address = addresses.firstOrNull { it is Inet4Address }
            ?: throw IllegalArgumentException("SOCKS5 proxy must resolve to IPv4")
        val first = address.address[0].toInt() and 0xff
        val second = address.address[1].toInt() and 0xff
        require(first != 100 || second !in 64..127) { "SOCKS5 proxy resolved to a mapdns address" }
        return address
    }

    private fun closeTunnel() {
        if (TProxyService.TProxyIsRunning()) TProxyService.TProxyStopService()
        if (tunnelFd >= 0) {
            try { ParcelFileDescriptor.adoptFd(tunnelFd).close() } catch (_: Exception) {}
            tunnelFd = -1
        }
        runningProfile = null
        tunnelOwner = null
    }

    private fun stopTunnel() {
        closeTunnel()
        if (Build.VERSION.SDK_INT >= 24) stopForeground(STOP_FOREGROUND_REMOVE) else {
            @Suppress("DEPRECATION") stopForeground(true)
        }
        stopSelf()
    }

    override fun onDestroy() {
        executor.execute { if (tunnelOwner === this) closeTunnel() }
        super.onDestroy()
    }

    private fun notification(profile: String): android.app.Notification {
        if (Build.VERSION.SDK_INT >= 26) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(channelId, "Proxy cấu hình", NotificationManager.IMPORTANCE_LOW),
            )
        }
        val open = PendingIntent.getActivity(
            this, 0, Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT,
        )
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.mipmap.launcher_icon)
            .setContentTitle("Proxy SOCKS5 đang hoạt động")
            .setContentText(profile)
            .setContentIntent(open)
            .setOngoing(true)
            .build()
    }

    private fun buildConfig(host: String, port: Int, username: String, password: String): String = """
        tunnel:
          name: tun0
          mtu: 1500
          multi-queue: false
          ipv4: '198.18.0.1'
          ipv6: ''
        socks5:
          address: '${yaml(host)}'
          port: $port
          udp: 'udp'
          username: '${yaml(username)}'
          password: '${yaml(password)}'
        # Generic SOCKS5 proxies cannot carry DNS (UDP). mapdns answers with
        # fake IPs from 100.64.0.0/10 and sends the hostname to the proxy, so
        # names resolve on the proxy side (like socks5h) and never leak.
        mapdns:
          address: '$mapDnsAddress'
          port: 53
          network: '100.64.0.0'
          netmask: '255.192.0.0'
          cache-size: 10000
        misc:
          connect-timeout: 15000
          tcp-read-write-timeout: 600000
          udp-read-write-timeout: 60000
          log-level: warn
    """.trimIndent()

    private fun yaml(value: String) = value.replace("'", "''")

    /** Covers all IPv4 addresses except the SOCKS server itself, avoiding a VPN loop. */
    private fun routesExcluding(bytes: ByteArray): List<Pair<String, Int>> {
        val target = bytes.fold(0L) { value, byte -> (value shl 8) or (byte.toLong() and 0xff) }
        return (1..32).map { prefix ->
            val shift = 32 - prefix
            val parentMask = if (prefix == 1) 0L else (0xffffffffL shl (shift + 1)) and 0xffffffffL
            val siblingBit = 1L shl shift
            val network = (target and parentMask) or ((target xor siblingBit) and siblingBit)
            val address = InetAddress.getByAddress(byteArrayOf(
                (network shr 24).toByte(), (network shr 16).toByte(),
                (network shr 8).toByte(), network.toByte(),
            )).hostAddress!!
            address to prefix
        }
    }
}
