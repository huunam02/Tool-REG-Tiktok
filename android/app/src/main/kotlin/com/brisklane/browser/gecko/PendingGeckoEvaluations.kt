package com.brisklane.browser.gecko

import java.util.concurrent.ConcurrentHashMap

/** Every bridge call belongs to one document and must finish exactly once. */
internal class PendingGeckoEvaluations<P : Any>(
    private val schedule: (Runnable, Long) -> Unit,
    private val cancel: (Runnable) -> Unit,
) {
    private data class Request<P>(
        val port: P,
        val callback: (Any?, String?) -> Unit,
        val timeout: Runnable,
    )
    private val requests = ConcurrentHashMap<String, Request<P>>()

    fun add(id: String, port: P, timeoutMs: Long, callback: (Any?, String?) -> Unit) {
        val timeout = Runnable {
            finish(id, null, "The page did not respond before the JavaScript timeout")
        }
        requests[id] = Request(port, callback, timeout)
        schedule(timeout, timeoutMs)
    }

    fun reply(id: String, port: P, value: Any?, error: String?) {
        if (requests[id]?.port === port) finish(id, value, error)
    }

    fun finish(id: String, value: Any?, error: String?) {
        val request = requests.remove(id) ?: return
        cancel(request.timeout)
        request.callback(value, error)
    }

    fun disconnect(port: P, error: String) {
        requests.entries.filter { it.value.port === port }.forEach {
            finish(it.key, null, error)
        }
    }

    fun close() {
        requests.keys.toList().forEach { finish(it, null, "GeckoView was disposed") }
    }
}
