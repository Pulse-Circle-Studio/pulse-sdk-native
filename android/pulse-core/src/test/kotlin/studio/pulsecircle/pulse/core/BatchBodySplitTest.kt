package studio.pulsecircle.pulse.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import studio.pulsecircle.pulse.core.testkit.ImmediateExecutor
import studio.pulsecircle.pulse.core.testkit.InMemoryKeyValueStorage
import studio.pulsecircle.pulse.core.testkit.InMemoryQueueStorage
import studio.pulsecircle.pulse.core.testkit.MockTransport
import studio.pulsecircle.pulse.core.testkit.RecordingLogger
import studio.pulsecircle.pulse.core.testkit.VirtualClock
import java.util.Random
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class BatchBodySplitTest {

    private val transport = MockTransport()
    private val client = PulseClient(
        apiKey = "pk_test",
        options = PulseOptions(flushAt = 100_000, flushIntervalMs = 86_400_000),
        executor = ImmediateExecutor(),
        clock = VirtualClock(),
        transport = transport,
        keyValueStorage = InMemoryKeyValueStorage(),
        queueStorage = InMemoryQueueStorage(),
        logger = RecordingLogger(),
        random = Random(7),
    )

    @Test
    fun `bodies over 512KB split into multiple batches preserving order`() {
        val pad = "x".repeat(100_000)
        val total = 8
        repeat(total) { n ->
            client.track("big", mapOf("i" to n, "pad" to pad))
        }
        client.flush()

        val seenIndexes = mutableListOf<Int>()
        var requests = 0
        while (true) {
            val pending = transport.takeOldest() ?: break
            requests++
            val bodyBytes = pending.request.body.toByteArray(Charsets.UTF_8).size
            assertTrue(
                bodyBytes <= PulseClient.MAX_BODY_BYTES,
                "request #$requests body is $bodyBytes bytes, over the 512KB cap"
            )
            val batch = Json.parseToJsonElement(pending.request.body).jsonObject.getValue("batch").jsonArray
            assertTrue(batch.isNotEmpty())
            for (item in batch) {
                seenIndexes.add(
                    item.jsonObject.getValue("properties").jsonObject.getValue("i").jsonPrimitive.int
                )
            }
            pending.callback(HttpResult.Response(200, "{}"))
        }

        assertTrue(requests >= 2, "expected the 800KB of events to split into at least two requests")
        assertEquals((0 until total).toList(), seenIndexes, "events must be delivered exactly once, in order")
    }

    @Test
    fun `a single event larger than 512KB is still sent alone`() {
        client.track("huge", mapOf("pad" to "y".repeat(600_000)))
        client.flush()

        val pending = transport.takeOldest()
        assertTrue(pending != null, "the oversized event must still be attempted")
        val batch = Json.parseToJsonElement(pending.request.body).jsonObject.getValue("batch").jsonArray
        assertEquals(1, batch.size)
        pending.callback(HttpResult.Response(200, "{}"))
        assertTrue(transport.pending.isEmpty())
    }
}
