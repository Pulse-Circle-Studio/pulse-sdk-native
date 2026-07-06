package studio.pulsecircle.pulse.core.fixtures

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import studio.pulsecircle.pulse.core.HttpResult
import studio.pulsecircle.pulse.core.PulseClient
import studio.pulsecircle.pulse.core.PulseOptions
import studio.pulsecircle.pulse.core.testkit.ImmediateExecutor
import studio.pulsecircle.pulse.core.testkit.InMemoryKeyValueStorage
import studio.pulsecircle.pulse.core.testkit.InMemoryQueueStorage
import studio.pulsecircle.pulse.core.testkit.MockTransport
import studio.pulsecircle.pulse.core.testkit.RecordingLogger
import studio.pulsecircle.pulse.core.testkit.VirtualClock
import java.io.IOException
import java.net.URI

/**
 * Executes one conformance fixture per FIXTURES.md against a real
 * [PulseClient] wired with the mock transport, virtual clock and in-memory
 * storages. The immediate synchronous executor makes every step settle
 * deterministically before the next one is evaluated.
 */
class FixtureRunner(private val fixture: JsonObject) {

    private val fixtureName = fixture["name"]?.jsonPrimitive?.content ?: "<unnamed>"
    private val executor = ImmediateExecutor()
    private val clock = VirtualClock()
    private val transport = MockTransport()
    private val keyValueStorage = InMemoryKeyValueStorage()
    private val queueStorage = InMemoryQueueStorage()
    private val logger = RecordingLogger()
    private val captures = HashMap<String, String>()
    private val matcher = FixtureMatcher(captures)

    private var client: PulseClient? = null
    private var initApiKey = ""
    private var initOptions = PulseOptions()

    fun run() {
        val steps = fixture.getValue("steps").jsonArray
        for ((index, stepElement) in steps.withIndex()) {
            val step = stepElement.jsonObject
            val action = step.getValue("do").jsonPrimitive.content
            try {
                runStep(action, step)
            } catch (t: Throwable) {
                throw AssertionError("fixture '$fixtureName', step #$index ('$action'): ${t.message}", t)
            }
        }
        check(transport.pending.isEmpty()) {
            "fixture '$fixtureName': ${transport.pending.size} pending request(s) were never consumed " +
                "by an expectRequest step: ${transport.pending.map { it.request.url }}"
        }
    }

    private fun runStep(action: String, step: JsonObject) {
        when (action) {
            "init" -> {
                initApiKey = step.getValue("apiKey").jsonPrimitive.content
                initOptions = parseOptions(step["options"])
                createClient()
            }

            "track" -> requireClient().track(
                step.getValue("event").jsonPrimitive.content,
                step["properties"]?.let { toKotlinMap(it.jsonObject) }
            )

            "trackMany" -> {
                val count = step.getValue("count").jsonPrimitive.int
                val event = step.getValue("event").jsonPrimitive.content
                val indexProperty = step.getValue("indexProperty").jsonPrimitive.content
                repeat(count) { n ->
                    requireClient().track(event, mapOf(indexProperty to n))
                }
            }

            "identify" -> requireClient().identify(step.getValue("userId").jsonPrimitive.content)

            "reset" -> requireClient().reset()

            "flush" -> requireClient().flush()

            "advance" -> clock.advance(step.getValue("ms").jsonPrimitive.longOrNull ?: 0)

            "restart" -> {
                // Simulated process death: the client is dropped without
                // flushing, its timers die, storage survives.
                client = null
                clock.cancelAllTimers()
                createClient()
            }

            "expectRequest" -> expectRequest(step)

            "expectNoRequest" -> check(transport.pending.isEmpty()) {
                "expected no pending request, but found: " +
                    transport.pending.map { it.request.url }
            }

            else -> error("unknown fixture step '$action'")
        }
    }

    private fun createClient() {
        client = PulseClient(
            apiKey = initApiKey,
            options = initOptions,
            executor = executor,
            clock = clock,
            transport = transport,
            keyValueStorage = keyValueStorage,
            queueStorage = queueStorage,
            logger = logger,
            random = java.util.Random(20260101),
            sdkName = "pulse-android",
        )
    }

    private fun requireClient(): PulseClient = checkNotNull(client) { "no client: missing init step" }

    private fun parseOptions(element: JsonElement?): PulseOptions {
        val defaults = PulseOptions()
        val obj = element?.jsonObject ?: return defaults
        return defaults.copy(
            flushAt = obj["flushAt"]?.jsonPrimitive?.int ?: defaults.flushAt,
            flushIntervalMs = obj["flushIntervalMs"]?.jsonPrimitive?.longOrNull ?: defaults.flushIntervalMs,
            maxQueueEvents = obj["maxQueueEvents"]?.jsonPrimitive?.int ?: defaults.maxQueueEvents,
            debug = obj["debug"]?.jsonPrimitive?.booleanOrNull ?: defaults.debug,
        )
    }

    private fun expectRequest(step: JsonObject) {
        val pending = transport.takeOldest()
        checkNotNull(pending) { "expected a request, but none is pending" }

        val expected = step.getValue("request").jsonObject

        val expectedPath = expected.getValue("path").jsonPrimitive.content
        val actualPath = URI(pending.request.url).path
        check(actualPath == expectedPath) { "path: expected $expectedPath, got $actualPath" }

        expected["headers"]?.jsonObject?.let { expectedHeaders ->
            val actualHeaders = pending.request.headers.mapKeys { it.key.lowercase() }
            for ((name, value) in expectedHeaders) {
                val expectedValue = value.jsonPrimitive.content
                val actualValue = actualHeaders[name.lowercase()]
                check(actualValue == expectedValue) {
                    "header '$name': expected \"$expectedValue\", got ${actualValue?.let { "\"$it\"" } ?: "<absent>"}"
                }
            }
        }

        val actualBody = Json.parseToJsonElement(pending.request.body)
        expected["body"]?.let { expectedBody ->
            matcher.match(expectedBody, actualBody, "body")
        }

        val respond = step.getValue("respond").jsonObject
        if (respond["networkError"]?.jsonPrimitive?.booleanOrNull == true) {
            pending.callback(HttpResult.NetworkError(IOException("fixture: scripted network error")))
        } else {
            val status = respond.getValue("status").jsonPrimitive.int
            val bodyTemplate = respond["body"] ?: JsonObject(emptyMap())
            val rendered = renderResponseTemplate(bodyTemplate, batchKeysOf(actualBody))
            pending.callback(HttpResult.Response(status, rendered.toString()))
        }
    }

    /** Every idempotency_key in the matched request's batch, in order. */
    private fun batchKeysOf(requestBody: JsonElement): List<String> = try {
        requestBody.jsonObject["batch"]?.jsonArray
            ?.map { it.jsonObject.getValue("idempotency_key").jsonPrimitive.content }
            ?: emptyList()
    } catch (_: Exception) {
        emptyList()
    }

    private fun renderResponseTemplate(template: JsonElement, keys: List<String>): JsonElement {
        return when (template) {
            is JsonObject -> JsonObject(template.mapValues { renderResponseTemplate(it.value, keys) })
            is JsonArray -> JsonArray(template.map { renderResponseTemplate(it, keys) })
            is JsonPrimitive -> {
                if (template.isString) {
                    val content = template.content
                    when {
                        content == "\$allKeys" -> JsonArray(keys.map { JsonPrimitive(it) })
                        content.startsWith("\$key:") -> {
                            val index = content.substring("\$key:".length).toInt()
                            JsonPrimitive(keys[index])
                        }
                        else -> template
                    }
                } else {
                    template
                }
            }
        }
    }

    /** Fixture JSON properties → the Map<String, Any?> the public API takes. */
    private fun toKotlinMap(obj: JsonObject): Map<String, Any?> =
        obj.mapValues { (_, value) -> toKotlin(value) }

    private fun toKotlin(element: JsonElement): Any? = when (element) {
        is JsonNull -> null
        is JsonObject -> element.mapValues { toKotlin(it.value) }
        is JsonArray -> element.map { toKotlin(it) }
        is JsonPrimitive -> when {
            element.isString -> element.content
            element.booleanOrNull != null -> element.booleanOrNull
            element.longOrNull != null -> element.longOrNull
            element.doubleOrNull != null -> element.doubleOrNull
            else -> element.content
        }
    }
}
