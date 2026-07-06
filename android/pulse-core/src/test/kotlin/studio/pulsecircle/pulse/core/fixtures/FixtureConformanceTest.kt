package studio.pulsecircle.pulse.core.fixtures

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.jupiter.api.Assumptions
import org.junit.jupiter.api.DynamicTest
import org.junit.jupiter.api.TestFactory
import java.io.File

/**
 * Runs every protocol conformance fixture from protocol/fixtures against the
 * real client (see FIXTURES.md). Fixtures whose `platforms` list excludes
 * "android" are skipped.
 */
class FixtureConformanceTest {

    @TestFactory
    fun conformanceFixtures(): List<DynamicTest> {
        val dirProperty = System.getProperty("pulse.fixtures.dir")
            ?: error("system property 'pulse.fixtures.dir' is not set (configured in build.gradle.kts)")
        val dir = File(dirProperty)
        val files = dir.listFiles { file -> file.name.endsWith(".json") }?.sortedBy { it.name }
        check(!files.isNullOrEmpty()) { "no fixture files found at $dir" }

        return files.map { file ->
            DynamicTest.dynamicTest(file.name) {
                val fixture = Json.parseToJsonElement(file.readText(Charsets.UTF_8)).jsonObject
                val platforms = fixture["platforms"]?.jsonArray?.map { it.jsonPrimitive.content }
                Assumptions.assumeTrue(
                    platforms == null || "android" in platforms,
                    "fixture '${file.name}' is restricted to platforms $platforms"
                )
                FixtureRunner(fixture).run()
            }
        }
    }
}
