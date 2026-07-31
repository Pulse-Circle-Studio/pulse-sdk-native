import com.vanniktech.maven.publish.JavadocJar
import com.vanniktech.maven.publish.KotlinJvm
import org.jetbrains.kotlin.gradle.dsl.JvmTarget

plugins {
    kotlin("jvm")
    kotlin("plugin.serialization")
    id("com.vanniktech.maven.publish")
}

group = "studio.pulsecircle.pulse"
version = "0.1.0"

java {
    sourceCompatibility = JavaVersion.VERSION_1_8
    targetCompatibility = JavaVersion.VERSION_1_8
    // No withSourcesJar(): the maven.publish plugin adds the sources jar
    // itself (KotlinJvm(sourcesJar = true) below); both would collide.
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

mavenPublishing {
    // Maven Central via the Central Portal (central.sonatype.com) — legacy
    // OSSRH was sunset in June 2025, new namespaces publish through the
    // portal only. Credentials/key arrive as ORG_GRADLE_PROJECT_* env vars:
    // mavenCentralUsername / mavenCentralPassword (portal token) and
    // signingInMemoryKey / signingInMemoryKeyPassword (armored GPG key);
    // see .github/workflows/publish.yml and RELEASING.md.
    publishToMavenCentral()
    // Tolerant of a missing key, as before the plugin migration: sign only
    // when one is supplied (ORG_GRADLE_PROJECT_signingInMemoryKey — always
    // set in CI), so local publishToMavenLocal works without GPG.
    if (findProperty("signingInMemoryKey") != null) {
        signAllPublications()
    }
    // Central requires a javadoc jar to exist; this build has no dokka, so
    // publish an empty one alongside the real sources jar.
    configure(KotlinJvm(javadocJar = JavadocJar.Empty(), sourcesJar = true))
    coordinates(group.toString(), "pulse-sdk-core", version.toString())

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
