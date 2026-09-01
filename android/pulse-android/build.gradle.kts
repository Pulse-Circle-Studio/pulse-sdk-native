plugins {
    id("com.android.library")
    kotlin("android")
    id("org.jetbrains.dokka")
    `maven-publish`
    signing
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

    publishing {
        singleVariant("release") {
            withSourcesJar()
            // No withJavadocJar(): AGP's jar would be empty on Kotlin sources
            // and it would collide with the Dokka-backed one attached below.
        }
    }
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

// Maven Central rejects a deployment with no -javadoc.jar ("Javadocs must be
// provided but not found in entries") — that is what failed the 0.1.0
// promotion. Built from Dokka rather than the `javadoc` task, which is
// NO-SOURCE on Kotlin sources and would ship an empty jar; this module holds
// the API consumers actually read (Pulse.init/track/identify).
val javadocJar by tasks.registering(Jar::class) {
    archiveClassifier.set("javadoc")
    from(tasks.named("dokkaJavadoc"))
}

afterEvaluate {
    publishing {
        publications {
            create<MavenPublication>("release") {
                from(components["release"])
                artifact(javadocJar)
                artifactId = "pulse-sdk-android"
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
        }
    }

    signing {
        // Same contract as :pulse-core — blank is missing, absent passphrase
        // is an empty string (see the comment there).
        val signingKey = (findProperty("signingKey") as String? ?: System.getenv("PULSE_SIGNING_KEY"))
            ?.takeIf { it.isNotBlank() }
        val signingPassword = (findProperty("signingPassword") as String?
            ?: System.getenv("PULSE_SIGNING_PASSWORD")) ?: ""
        if (signingKey != null) {
            useInMemoryPgpKeys(signingKey, signingPassword)
        }
        isRequired = signingKey != null
        sign(publishing.publications)
    }
}
