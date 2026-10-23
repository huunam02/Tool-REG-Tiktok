package com.brisklane.browser.gecko

import org.junit.Assert.*
import org.junit.Test

class PendingGeckoEvaluationsTest {
    private class Clock {
        val tasks = linkedMapOf<Runnable, Long>()
        val calls = PendingGeckoEvaluations<Any>(
            schedule = { task, delay -> tasks[task] = delay },
            cancel = { task -> tasks.remove(task); Unit },
        )
        fun expire() = tasks.keys.toList().forEach { it.run() }
    }

    @Test fun lostReplyTimesOutOnceAndLateReplyIsIgnored() {
        val clock = Clock()
        val port = Any()
        var count = 0
        clock.calls.add("lost", port, 30_000L) { value, error ->
            count++
            assertNull(value)
            assertTrue(error!!.contains("timeout"))
        }
        assertEquals(30_000L, clock.tasks.values.single())
        clock.expire()
        clock.calls.reply("lost", port, "late reply", null)
        clock.calls.close()
        assertEquals(1, count)
        assertTrue(clock.tasks.isEmpty())
    }

    @Test fun disconnectOnlyFailsRequestsForThatDocument() {
        val clock = Clock()
        val old = Any()
        val current = Any()
        val results = mutableListOf<String>()
        clock.calls.add("old", old, 30_000L) { _, error -> results += error!! }
        clock.calls.add("current", current, 30_000L) { value, _ -> results += value as String }
        clock.calls.disconnect(old, "document disconnected")
        clock.calls.reply("current", old, "wrong document", null)
        assertEquals(listOf("document disconnected"), results)
        clock.calls.reply("current", current, "new document works", null)
        clock.expire()
        assertEquals(listOf("document disconnected", "new document works"), results)
        assertTrue(clock.tasks.isEmpty())
    }

    @Test fun successfulReplyCancelsTimeoutWithoutRepeatingTheCallback() {
        val clock = Clock()
        val port = Any()
        var count = 0
        clock.calls.add("ok", port, 10L) { value, error ->
            count++
            assertEquals(2, value)
            assertNull(error)
        }
        clock.calls.reply("ok", port, 2, null)
        clock.expire()
        assertEquals(1, count)
        assertTrue(clock.tasks.isEmpty())
    }

    @Test fun disposeReleasesAllPendingCallsAndTimers() {
        val clock = Clock()
        var count = 0
        for (id in listOf("first", "second")) {
            clock.calls.add(id, Any(), 30_000L) { _, error ->
                count++
                assertEquals("GeckoView was disposed", error)
            }
        }
        clock.calls.close()
        clock.calls.close()
        assertEquals(2, count)
        assertTrue(clock.tasks.isEmpty())
    }
}
