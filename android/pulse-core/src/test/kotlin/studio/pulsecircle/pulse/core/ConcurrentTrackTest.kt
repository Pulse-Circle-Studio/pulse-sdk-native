package studio.pulsecircle.pulse.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import studio.pulsecircle.pulse.core.testkit.InMemoryKeyValueStorage
import studio.pulsecircle.pulse.core.testkit.InMemoryQueueStorage
import studio.pulsecircle.pulse.core.testkit.MockTransport
import studio.pulsecircle.pulse.core.testkit.RecordingLogger
import studio.pulsecircle.pulse.core.testkit.VirtualClock
import java.util.Random
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/**
 * All public methods hand off to the single-thread executor: calling track()
 * concurrently from many threads must lose nothing and preserve each
 * thread's own ordering.
 */
class ConcurrentTrackTest {

    @Test
    fun `concurrent track from 8 threads queues every event with per-thread order preserved`() {
        val threads = 8
        val eventsPerThread = 250
        val executor = SingleThreadPulseExecutor("pulse-test")
        val transport = MockTransport()
        val queueStorage = InMemoryQueueStorage()
        val client = PulseClient(
            apiKey = "pk_test",
            options = PulseOptions(
                flushAt = Int.MAX_VALUE,
                flushIntervalMs = 86_400_000,
                maxQueueEvents = Int.MAX_VALUE,
            ),
            executor = executor,
            clock = VirtualClock(),
            transport = transport,
            keyValueStorage = InMemoryKeyValueStorage(),
            queueStorage = queueStorage,
            logger = RecordingLogger(),
            random = Random(11),
        )

        try {
            val startGate = CountDownLatch(1)
            val workers = (0 until threads).map { t ->
                Thread {
                    startGate.await()
                    for (i in 0 until eventsPerThread) {
                        client.track("concurrent", mapOf("t" to t, "i" to i))
                    }
                }.apply { start() }
            }
            startGate.countDown()
            workers.forEach { it.join(30_000) }

            // Drain the executor so every handed-off track() has run.
            val settled = CountDownLatch(1)
            executor.execute { settled.countDown() }
            assertTrue(settled.await(30, TimeUnit.SECONDS), "executor did not settle")

            assertTrue(transport.pending.isEmpty(), "no flush should have happened")
            assertEquals(threads * eventsPerThread, queueStorage.items.size, "every event must be queued")

            val perThread = HashMap<Int, MutableList<Int>>()
            for (line in queueStorage.items) {
                val properties = Json.parseToJsonElement(line).jsonObject.getValue("properties").jsonObject
                val t = properties.getValue("t").jsonPrimitive.int
                val i = properties.getValue("i").jsonPrimitive.int
                perThread.getOrPut(t) { mutableListOf() }.add(i)
            }
            assertEquals(threads, perThread.size)
            for ((t, indexes) in perThread) {
                assertEquals(
                    (0 until eventsPerThread).toList(),
                    indexes,
                    "thread $t's events must appear in submission order"
                )
            }
        } finally {
            executor.shutdown()
        }
    }
}
