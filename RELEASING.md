# Releasing (pulse-sdk-native)

The two platforms release independently, each from a prefixed git tag.

## iOS

1. Bump `s.version` in `PulseSDK.podspec`.
2. Land on `main` with green CI (`swift test`, `pod lib lint`).
3. Tag and push:

   ```bash
   git tag ios-v0.1.0
   git push origin ios-v0.1.0
   ```

   - **Swift Package Manager** needs no publish step — the git tag *is* the
     release. Consumers pin `from: "0.1.0"`; Xcode resolves the tag. (The
     publish workflow validates the podspec version against the tag.)
   - **CocoaPods**: the workflow runs `pod trunk push` using the
     `COCOAPODS_TRUNK_TOKEN` secret.

## Android

1. Bump `version` in `android/pulse-core/build.gradle.kts` and
   `android/pulse-android/build.gradle.kts`.
2. Land on `main` with green CI (`:pulse-core:test`, `:pulse-android:assembleRelease`).
3. Tag and push:

   ```bash
   git tag android-v0.1.0
   git push origin android-v0.1.0
   ```

   The workflow publishes `pulse-sdk-core` (JAR) and `pulse-sdk-android` (AAR)
   to Maven Central via Sonatype.

## Secrets

| Secret | Used by |
|---|---|
| `COCOAPODS_TRUNK_TOKEN` | `pod trunk push` (iOS) |
| `SONATYPE_USERNAME`, `SONATYPE_PASSWORD` | Maven Central upload (Android) |
| `PULSE_SIGNING_KEY`, `PULSE_SIGNING_PASSWORD` | GPG signing of Maven artifacts |

## Fixture parity

CI's `fixtures-identity` job diffs `protocol/fixtures` and `protocol/PROTOCOL.md`
against the canonical copies in the
[pulse-sdk](https://github.com/Pulse-Circle-Studio/pulse-sdk) repo. If you
change the protocol, update it there first, then sync the vendored copy here
in the same release.
