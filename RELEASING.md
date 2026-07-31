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
     release, but SPM only resolves **bare semver tags**, so push one too:
     `git tag 0.1.0 && git push origin 0.1.0`. Consumers pin `from: "0.1.0"`.
     (The publish workflow validates the podspec version against the `ios-v*`
     tag; the podspec's `s.source` also points at the bare tag.)
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
   to Maven Central through the **Central Portal** (central.sonatype.com) and
   auto-releases the validated deployments (`publishAndReleaseToMavenCentral`
   from the `com.vanniktech.maven.publish` plugin). Legacy OSSRH
   (oss.sonatype.org) is sunset — don't point credentials there.

### One-time Maven Central setup

1. Create an account on [central.sonatype.com](https://central.sonatype.com)
   and register the namespace `studio.pulsecircle` — verified with a DNS TXT
   record on `pulsecircle.studio`.
2. Generate a user token there (Account → Generate User Token). It is a
   username/password pair → the `SONATYPE_USERNAME` / `SONATYPE_PASSWORD`
   secrets.
3. Create a GPG key and publish its public part:

   ```bash
   gpg --gen-key
   gpg --keyserver keyserver.ubuntu.com --send-keys <KEYID>
   gpg --export-secret-keys --armor <KEYID>   # → PULSE_SIGNING_KEY secret
   ```

### One-time CocoaPods setup

`pod trunk register <email> 'Pulse Circle Studio'` (registration IS account
creation — there is no separate signup), click the confirmation link in the
email, then copy the token from `~/.netrc` (the `trunk.cocoapods.org` entry)
into the `COCOAPODS_TRUNK_TOKEN` secret. Requires a local CocoaPods install
(`brew install cocoapods`). Before registering, check the pod name is still
free: `pod trunk info PulseSDK` should say "No pod found".

## Secrets

| Secret | Used by |
|---|---|
| `COCOAPODS_TRUNK_TOKEN` | `pod trunk push` (iOS) |
| `SONATYPE_USERNAME`, `SONATYPE_PASSWORD` | Central Portal user token (Maven Central upload, Android) |
| `PULSE_SIGNING_KEY`, `PULSE_SIGNING_PASSWORD` | GPG signing of Maven artifacts (armored private key + its passphrase) |

## Fixture parity

CI's `fixtures-identity` job diffs `protocol/fixtures` and `protocol/PROTOCOL.md`
against the canonical copies in the
[pulse-sdk](https://github.com/Pulse-Circle-Studio/pulse-sdk) repo. If you
change the protocol, update it there first, then sync the vendored copy here
in the same release.
