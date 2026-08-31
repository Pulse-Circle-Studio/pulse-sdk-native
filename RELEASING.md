# Releasing (pulse-sdk-native)

The two platforms release independently. iOS releases from a **bare semver
tag**; Android from an `android-v` prefixed tag.

## iOS

1. Bump `s.version` in `pulse-circle.podspec`.
2. Land on `main` with green CI (`swift test`, `pod lib lint`).
3. Tag and push — the tag must be bare semver (`0.1.1`) or `v`-prefixed
   (`v0.1.1`), **never** `ios-v0.1.1`:

   ```bash
   git tag 0.1.1
   git push origin 0.1.1
   ```

   - **Swift Package Manager** needs no publish step — the git tag *is* the
     release. This is why the prefix matters: SPM only resolves bare semver or
     `vX.Y.Z` tags, so an `ios-v…` tag would be invisible to Xcode. Consumers
     pin `from: "0.1.1"`.
   - **CocoaPods**: the same tag triggers `pod trunk push` using the
     `COCOAPODS_TRUNK_TOKEN` secret. The pod is named **`pulse-circle`** —
     `PulseSDK` was registered by an unrelated project in 2014 — but
     `s.module_name` keeps it `PulseSDK`, so consumers `import PulseSDK` on
     both channels. The podspec's `s.source` uses `:tag => s.version.to_s`, so
     the tag name and `s.version` must match exactly.

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
   to Maven Central.

### One-time Maven Central setup

OSSRH (`oss.sonatype.org`, `s01.oss.sonatype.org`) was sunset on 30 June 2025
and now returns `402`. Publishing goes through the **Central Portal**; the build
uploads via Sonatype's OSSRH Staging API compatibility service, which speaks the
Nexus 2 API that `maven-publish` already knows.

1. **Claim the namespace.** Sign in at [central.sonatype.com](https://central.sonatype.com)
   → Namespaces → Add Namespace → `studio.pulsecircle`. Maven namespaces are
   reverse-DNS, so this is simply `pulsecircle.studio` backwards — `studio` is
   the TLD, not a word. Add the verification key it gives you as a **DNS TXT
   record on `pulsecircle.studio`**, then press Verify. This covers the
   `studio.pulsecircle.pulse` group id used here as a subgroup.
2. **User token.** Portal → Account → Generate User Token. The username and
   password it returns are the `SONATYPE_USERNAME` / `SONATYPE_PASSWORD`
   secrets — *not* your portal login.
3. **Signing key.** Maven Central requires PGP-signed artifacts:

   ```bash
   gpg --quick-generate-key "Pulse Circle Studio <rost@pulsecircle.studio>" rsa4096 sign never
   gpg --list-secret-keys --keyid-format=long        # note the key id
   gpg --keyserver keyserver.ubuntu.com --send-keys <KEY_ID>
   gpg --armor --export-secret-keys <KEY_ID>         # value for PULSE_SIGNING_KEY
   ```

4. After the first upload, releases land in the Portal as a staged deployment —
   publish it there once, then subsequent releases can be set to auto-publish.

## Secrets

All of these live in **this** repository (`pulse-sdk-native`) →
Settings → Secrets and variables → Actions.

| Secret | Used by | Where it comes from |
|---|---|---|
| `COCOAPODS_TRUNK_TOKEN` | `pod trunk push` (iOS) | `pod trunk register <email> '<name>'`, confirm the emailed link, then read the `password` value under `machine trunk.cocoapods.org` in `~/.netrc`. It is a session token, not your account password. |
| `SONATYPE_USERNAME`, `SONATYPE_PASSWORD` | Maven Central upload | Portal user token (step 2 above) |
| `PULSE_SIGNING_KEY`, `PULSE_SIGNING_PASSWORD` | GPG signing of Maven artifacts | Armored private key + its passphrase (step 3 above) |

## Fixture parity

CI's `fixtures-identity` job diffs `protocol/fixtures` and `protocol/PROTOCOL.md`
against the canonical copies in the
[pulse-sdk](https://github.com/Pulse-Circle-Studio/pulse-sdk) repo. If you
change the protocol, update it there first, then sync the vendored copy here
in the same release.
