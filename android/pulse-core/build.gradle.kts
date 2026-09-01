import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
    id("org.jetbrains.dokka")
    `maven-publish`
    signing
}

group = "studio.pulsecircle.pulse"
version = "0.1.0"

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
    withSourcesJar()
    // Maven Central rejects a deployment with no -javadoc.jar ("Javadocs must
    // be provided but not found in entries") — that is what failed the 0.1.0
    // promotion. withJavadocJar() also wires the jar into the publication,
    // which a hand-registered task would not.
    withJavadocJar()
}

// ...but on Kotlin sources the `javadoc` task is NO-SOURCE, so that jar would
// ship empty and merely satisfy the check. Fill it from Dokka instead so
// consumers get real API docs.
tasks.named<Jar>("javadocJar") {
    from(tasks.named("dokkaJavadoc"))
}

kotlin {
    compilerOptions {
        // The Android AAR (minSdk 24) depends on this jar; stay on JVM 1.8 bytecode.
        jvmTarget.set(JvmTarget.JVM_1_8)
    }
}

dependencies {
    implementation("org.jetbrains.kotlinx:kotlinx-serialization-json:1.7.3")

    testImplementation(kotlin("test"))
    testImplementation("org.junit.jupiter:junit-jupiter:5.10.2")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    // android/pulse-core -> android -> repo root -> protocol/fixtures
    systemProperty(
        "pulse.fixtures.dir",
        projectDir.parentFile.parentFile.resolve("protocol/fixtures").absolutePath
    )
    testLogging {
        events("passed", "skipped", "failed")
    }
}

publishing {
    publications {
        create<MavenPublication>("maven") {
            from(components["java"])
            artifactId = "pulse-sdk-core"
            pom {
                name.set("Pulse SDK Core")
                description.set("Core event queue, batching, retry and identity engine for the Pulse analytics SDK (pure Kotlin/JVM).")
                url.set("https://github.com/Pulse-Circle-Studio/pulse-sdk-native")
                licenses {
                    license {
                        name.set("MIT License")
                        url.set("https://opensource.org/licenses/MIT")
                    }
                }
                developers {
                    developer {
                        id.set("pulse-circle-studio")
                        name.set("Pulse Circle Studio")
                    }
                }
                scm {
                    url.set("https://github.com/Pulse-Circle-Studio/pulse-sdk-native")
                    connection.set("scm:git:git://github.com/Pulse-Circle-Studio/pulse-sdk-native.git")
                    developerConnection.set("scm:git:ssh://git@github.com/Pulse-Circle-Studio/pulse-sdk-native.git")
                }
            }
        }
    }
}

signing {
    // Tolerant of missing keys: signing is only required (and only configured)
    // when a key is supplied via Gradle properties or the environment. Blank
    // counts as missing — an empty CI secret would otherwise be treated as a
    // key and fail with "Could not read PGP secret key".
    val signingKey = (findProperty("signingKey") as String? ?: System.getenv("PULSE_SIGNING_KEY"))
        ?.takeIf { it.isNotBlank() }
    // A key generated without a passphrase has none; useInMemoryPgpKeys needs
    // an empty string rather than null for that case.
    val signingPassword = (findProperty("signingPassword") as String?
        ?: System.getenv("PULSE_SIGNING_PASSWORD")) ?: ""
    if (signingKey != null) {
        useInMemoryPgpKeys(signingKey, signingPassword)
    }
    isRequired = signingKey != null
    sign(publishing.publications)
}
