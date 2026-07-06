package studio.pulsecircle.pulse.core.fixtures

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

/**
 * Structural, strict body matcher per FIXTURES.md: same object keys, same
 * array lengths, same order; numbers compare by value; expected strings
 * starting with `$` are matchers; a `batch` value may be a `$seq` object.
 */
class FixtureMatcher(private val captures: MutableMap<String, String>) {

    companion object {
        private val UUID4 = Regex(
            "[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-4[0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}"
        )
        private val EVENT_KEY = Regex("evt_[0-9A-HJKMNP-TV-Z]{26}")
        private val IDENTIFY_KEY = Regex("idf_[0-9A-HJKMNP-TV-Z]{26}")
        private val ISO_TIMESTAMP = Regex("\\d{4}-\\d{2}-\\d{2}T\\d{2}:\\d{2}:\\d{2}\\.\\d{3}Z")
    }

    fun match(expected: JsonElement, actual: JsonElement, path: String) {
        when (expected) {
            is JsonObject -> matchObject(expected, actual, path)
            is JsonArray -> matchArray(expected, actual, path)
            is JsonPrimitive -> matchPrimitive(expected, actual, path)
        }
    }

    private fun matchObject(expected: JsonObject, actual: JsonElement, path: String) {
        val seq = expected["\$seq"]
        if (seq != null && expected.size == 1) {
            matchSeq(seq.jsonObject, actual, path)
            return
        }
        check(actual is JsonObject) { "$path: expected an object, got $actual" }
        check(expected.keys == actual.keys) {
            "$path: object keys differ — expected ${expected.keys}, got ${actual.keys}"
        }
        for ((key, value) in expected) {
            match(value, actual.getValue(key), "$path.$key")
        }
    }

    private fun matchArray(expected: JsonArray, actual: JsonElement, path: String) {
        check(actual is JsonArray) { "$path: expected an array, got $actual" }
        check(expected.size == actual.size) {
            "$path: array length differs — expected ${expected.size}, got ${actual.size}"
        }
        for (index in expected.indices) {
            match(expected[index], actual[index], "$path[$index]")
        }
    }

    private fun matchPrimitive(expected: JsonPrimitive, actual: JsonElement, path: String) {
        if (expected is JsonNull) {
            check(actual is JsonNull) { "$path: expected null, got $actual" }
            return
        }
        check(actual is JsonPrimitive) { "$path: expected a primitive, got $actual" }
        if (expected.isString && expected.content.startsWith("$")) {
            check(actual.isString) { "$path: matcher '${expected.content}' requires a string, got $actual" }
            matchToken(expected.content, actual.content, path)
            return
        }
        if (expected.isString) {
            check(actual.isString && actual.content == expected.content) {
                "$path: expected \"${expected.content}\", got $actual"
            }
            return
        }
        check(!actual.isString) { "$path: expected ${expected.content}, got string $actual" }
        val expectedBoolean = expected.booleanOrNull
        if (expectedBoolean != null) {
            check(actual.booleanOrNull == expectedBoolean) { "$path: expected $expectedBoolean, got $actual" }
            return
        }
        val expectedNumber = expected.doubleOrNull
        if (expectedNumber != null) {
            check(actual.doubleOrNull == expectedNumber) { "$path: expected $expectedNumber, got $actual" }
            return
        }
        check(expected.content == actual.content) { "$path: expected $expected, got $actual" }
    }

    private fun matchToken(token: String, value: String, path: String) {
        when {
            token == "\$uuid4" || token == "\$eventKey" || token == "\$identifyKey" ||
                token == "\$isoTimestamp" || token == "\$string" ->
                matchBase(token.substring(1), value, path)

            token.startsWith("\$capture:") -> {
                val parts = token.split(":", limit = 3)
                check(parts.size == 3) { "$path: malformed capture matcher '$token'" }
                matchBase(parts[2], value, path)
                captures[parts[1]] = value
            }

            token.startsWith("\$same:") -> {
                val name = token.substring("\$same:".length)
                val captured = captures[name]
                check(captured != null) { "$path: \$same references unknown capture '$name'" }
                check(value == captured) { "$path: expected captured '$name' = \"$captured\", got \"$value\"" }
            }

            token.startsWith("\$differs:") -> {
                val parts = token.split(":", limit = 3)
                check(parts.size == 3) { "$path: malformed differs matcher '$token'" }
                val captured = captures[parts[1]]
                check(captured != null) { "$path: \$differs references unknown capture '${parts[1]}'" }
                matchBase(parts[2], value, path)
                check(value != captured) { "$path: expected a value different from capture '${parts[1]}' (\"$captured\")" }
            }

            else -> error("$path: unknown matcher '$token'")
        }
    }

    private fun matchBase(matcherName: String, value: String, path: String) {
        val ok = when (matcherName) {
            "uuid4" -> UUID4.matches(value)
            "eventKey" -> EVENT_KEY.matches(value)
            "identifyKey" -> IDENTIFY_KEY.matches(value)
            "isoTimestamp" -> ISO_TIMESTAMP.matches(value)
            "string" -> value.isNotEmpty()
            else -> error("$path: unknown base matcher '$matcherName'")
        }
        check(ok) { "$path: value \"$value\" does not match \$$matcherName" }
    }

    /**
     * `{"$seq": {"event", "indexProperty", "start", "count"}}` — a batch of
     * exactly `count` standard-shaped track events with `{"<ip>": start + i}`
     * properties, proving order end-to-end.
     */
    private fun matchSeq(spec: JsonObject, actual: JsonElement, path: String) {
        val event = spec.getValue("event").jsonPrimitive.content
        val indexProperty = spec.getValue("indexProperty").jsonPrimitive.content
        val start = spec.getValue("start").jsonPrimitive.int
        val count = spec.getValue("count").jsonPrimitive.int
        check(actual is JsonArray) { "$path: \$seq expects an array, got $actual" }
        check(actual.size == count) { "$path: \$seq expected $count items, got ${actual.size}" }
        val expectedKeys = setOf("type", "anonymous_id", "event", "properties", "idempotency_key", "timestamp")
        for (position in 0 until count) {
            val itemPath = "$path[$position]"
            val item = actual[position].jsonObject
            check(item.keys == expectedKeys) {
                "$itemPath: keys differ — expected $expectedKeys, got ${item.keys}"
            }
            check(item.getValue("type").jsonPrimitive.content == "track") { "$itemPath: type must be track" }
            check(item.getValue("event").jsonPrimitive.content == event) {
                "$itemPath: expected event \"$event\", got ${item["event"]}"
            }
            matchBase("uuid4", item.getValue("anonymous_id").jsonPrimitive.content, "$itemPath.anonymous_id")
            matchBase("eventKey", item.getValue("idempotency_key").jsonPrimitive.content, "$itemPath.idempotency_key")
            matchBase("isoTimestamp", item.getValue("timestamp").jsonPrimitive.content, "$itemPath.timestamp")
            val properties = item.getValue("properties").jsonObject
            check(properties.keys == setOf(indexProperty)) {
                "$itemPath.properties: expected exactly {\"$indexProperty\"}, got ${properties.keys}"
            }
            val expectedValue = (start + position).toDouble()
            val actualValue = properties.getValue(indexProperty).jsonPrimitive.doubleOrNull
            check(actualValue == expectedValue) {
                "$itemPath.properties.$indexProperty: expected ${start + position}, got ${properties[indexProperty]}"
            }
        }
    }
}
