import com.vanniktech.maven.publish.AndroidSingleVariantLibrary

plugins {
    id("com.android.library")
    kotlin("android")
    id("com.vanniktech.maven.publish")
}

group = "studio.pulsecircle.pulse"
version = "0.1.0"

android {
    namespace = "studio.pulsecircle.pulse.android"
    // 34 is the highest compileSdk tested with AGP 8.5.2; nothing here uses an
    // API above it (minSdk 24). Bump alongside AGP if you raise it.
    compileSdk = 34

    defaultConfig {
        minSdk = 24
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_1_8
        targetCompatibility = JavaVersion.VERSION_1_8
    }

    // No android.publishing.singleVariant here: the maven.publish plugin
    // declares the release-variant publication itself (see mavenPublishing).
}

kotlin {
    // Match the Java target above (1.8) so AGP's JVM-target validation passes;
    // the core JAR this AAR depends on is also 1.8 bytecode.
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_1_8)
    }
}

dependencies {
    // The AAR re-exports the pure-JVM core (public types like PulseOptions).
    api(project(":pulse-core"))
}

mavenPublishing {
    // Maven Central via the Central Portal — same setup as :pulse-core (see
    // the comment there and RELEASING.md for the credential env vars).
    publishToMavenCentral()
    // Sign only when a key is supplied (always set in CI) — see :pulse-core.
    if (findProperty("signingInMemoryKey") != null) {
        signAllPublications()
    }
    // Sources jar from the release variant; Central requires a javadoc jar
    // to exist, and with no dokka applied the plugin publishes an empty one.
    configure(AndroidSingleVariantLibrary("release", sourcesJar = true, publishJavadocJar = true))
    coordinates(group.toString(), "pulse-sdk-android", version.toString())

    pom {
        name.set("Pulse SDK for Android")
        description.set("Android analytics SDK: a reliable, offline-first event queue and identity over the Pulse ingestion protocol. Add analytics to your Android app in two lines.")
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
