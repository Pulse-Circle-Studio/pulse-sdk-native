pluginManagement {
    repositories {
        // gradlePluginPortal/mavenCentral first: the Kotlin plugins resolve from
        // there, so environments where dl.google.com is unreachable never touch
        // google(). google() is required for the Android Gradle Plugin in CI.
        gradlePluginPortal()
        mavenCentral()
        google()
    }
    // All plugin versions are pinned here (same classloader scope), so
    // :pulse-android can apply AGP + kotlin-android together without the
    // cross-classloader "KotlinAndroidTarget → BaseVariant" failure. AGP is
    // resolved lazily (from google()) only when :pulse-android is included, so
    // the JVM-only :pulse-core build never touches google()/dl.google.com.
    plugins {
        kotlin("jvm") version "2.0.21"
        kotlin("android") version "2.0.21"
        kotlin("plugin.serialization") version "2.0.21"
        id("com.android.library") version "8.5.2"
        id("com.vanniktech.maven.publish") version "0.34.0"
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
