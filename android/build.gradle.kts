// Root build file for the Pulse Android SDK.
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
