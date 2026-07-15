pluginManagement {
    repositories {
        // gradlePluginPortal/mavenCentral first: the Kotlin plugins resolve from
        // there, so environments where dl.google.com is unreachable never touch
        // google(). google() is required for the Android Gradle Plugin in CI.
        gradlePluginPortal()
        mavenCentral()
        google()
    }
    // Kotlin plugin versions live in the root build.gradle.kts (apply false).
    // The Android Gradle Plugin is applied only by :pulse-android, so its
    // version is pinned here and resolved lazily (from google()) only when that
    // module is included — keeping the JVM-only :pulse-core build off google().
    plugins {
        id("com.android.library") version "8.5.2"
    }
}

dependencyResolutionManagement {
    repositories {
        mavenCentral()
        google()
    }
}

rootProject.name = "pulse-sdk-android"

include(":pulse-core")

// :pulse-android needs the Android SDK (and the Android Gradle Plugin from
// dl.google.com). Include it only where an SDK is present — e.g. GitHub CI.
if (System.getenv("ANDROID_HOME") != null || System.getenv("ANDROID_SDK_ROOT") != null) {
    include(":pulse-android")
} else {
    logger.lifecycle(
        "Pulse: ANDROID_HOME/ANDROID_SDK_ROOT not set — skipping the :pulse-android module. " +
            "Only :pulse-core (pure JVM) is included in this build."
    )
}
