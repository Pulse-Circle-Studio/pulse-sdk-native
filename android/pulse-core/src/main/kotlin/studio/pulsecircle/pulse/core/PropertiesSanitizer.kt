package studio.pulsecircle.pulse.core

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/**
 * Properties sanitization per protocol §3: values are primitives
 * (string/number/boolean/null) or containers nested at most 2 levels deep.
 * A top-level value that violates the rule is dropped (with a debug warning);
 * the event itself is kept.
 */
internal object PropertiesSanitizer {

    private const val MAX_CONTAINER_DEPTH = 2

    fun sanitize(properties: Map<String, Any?>?, logger: PulseLogger): JsonObject {
        if (properties == null || properties.isEmpty()) return JsonObject(emptyMap())
        val out = LinkedHashMap<String, JsonElement>()
        for ((key, value) in properties) {
            val element = convert(value, MAX_CONTAINER_DEPTH)
            if (element == null) {
                logger.debug(
                    "Pulse: dropping property '$key' — nested deeper than " +
                        "$MAX_CONTAINER_DEPTH levels or not JSON-representable"
                )
            } else {
                out[key] = element
            }
        }
        return JsonObject(out)
    }

    private fun convert(value: Any?, remainingDepth: Int): JsonElement? {
        return when (value) {
            null -> JsonNull
            is String -> JsonPrimitive(value)
            is Boolean -> JsonPrimitive(value)
            is Number -> JsonPrimitive(value)
            is Map<*, *> -> {
                if (remainingDepth <= 0) return null
                val out = LinkedHashMap<String, JsonElement>()
                for ((k, v) in value) {
                    val key = k as? String ?: return null
                    val element = convert(v, remainingDepth - 1) ?: return null
                    out[key] = element
                }
                JsonObject(out)
            }
            is Iterable<*> -> {
                if (remainingDepth <= 0) return null
                val out = ArrayList<JsonElement>()
                for (v in value) {
                    val element = convert(v, remainingDepth - 1) ?: return null
                    out.add(element)
                }
                JsonArray(out)
            }
            is Array<*> -> convert(value.toList(), remainingDepth)
            else -> null
        }
    }
}
