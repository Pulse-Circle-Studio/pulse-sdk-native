// Root build file for the Pulse Android SDK.
// Plugin versions are declared here once (apply false) and applied without a
// version in the subprojects, so the Kotlin plugin is loaded a single time on
// the shared build classpath rather than independently per subproject.
// Only the Kotlin plugins are declared here (they're applied in BOTH
// subprojects — declaring once avoids the "loaded multiple times" warning).
// The Android Gradle Plugin is applied only in :pulse-android, so its version
// stays in settings.gradle.kts pluginManagement — declaring it here would force
// resolving it from dl.google.com even for the JVM-only :pulse-core build.
plugins {
    kotlin("jvm") version "2.0.21" apply false
    kotlin("android") version "2.0.21" apply false
    kotlin("plugin.serialization") version "2.0.21" apply false
}

// Per-module configuration lives in :pulse-core and :pulse-android; the shared
// Maven Central (Sonatype) publishing target is wired here for every module
// that applies the maven-publish plugin.
subprojects {
    plugins.withId("maven-publish") {
        extensions.configure<PublishingExtension> {
            repositories {
                maven {
                    name = "sonatype"
                    val releasesUrl = uri("https://s01.oss.sonatype.org/service/local/staging/deploy/maven2/")
                    val snapshotsUrl = uri("https://s01.oss.sonatype.org/content/repositories/snapshots/")
                    url = if (version.toString().endsWith("SNAPSHOT")) snapshotsUrl else releasesUrl
                    credentials {
                        username = (findProperty("sonatypeUsername") as String?) ?: System.getenv("SONATYPE_USERNAME")
                        password = (findProperty("sonatypePassword") as String?) ?: System.getenv("SONATYPE_PASSWORD")
                    }
                }
            }
        }
    }
}
