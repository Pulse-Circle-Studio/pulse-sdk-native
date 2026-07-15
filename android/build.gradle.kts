// Root build file for the Pulse Android SDK.
// NOTE: plugin versions are declared in settings.gradle.kts (pluginManagement),
// NOT here with `apply false`. Declaring the Kotlin plugins at the root scope
// while AGP is applied at the project scope puts them on different classloaders,
// which breaks org.jetbrains.kotlin.android with a "KotlinAndroidTarget →
// com/android/build/gradle/api/BaseVariant" NoClassDefFoundError. Keeping both
// in pluginManagement applies them in the same scope. The benign "Kotlin plugin
// loaded multiple times" warning is accepted as the cost of that correctness.
//
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
