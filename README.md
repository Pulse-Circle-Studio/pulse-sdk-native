# Pulse Native SDKs

The **iOS (Swift)** and **Android (Kotlin)** SDKs for
[Pulse](https://github.com/Pulse-Circle-Studio/pulse-sdk) analytics. Same API,
same wire protocol, and the same conformance fixtures as the web and React
Native SDKs — add analytics to your mobile app with a reliable, offline-first
event queue and clean identity, and nothing else.

- **Privacy-first.** No advertising ids, no location, no fingerprinting, no
  auto-capture. The SDK sends only the events you send it.
- **Reliable.** A persistent, ordered queue survives offline periods and
  process death. Delivery is idempotent — retries never duplicate events.
- **Lean.** iOS: no dependencies. Android: nothing beyond kotlinx-serialization.
  No background URLSession, no WorkManager.

| Platform | Directory | Distribution |
|---|---|---|
| iOS / Swift | [`ios/`](./ios) (package root: [`Package.swift`](./Package.swift)) | SPM + CocoaPods |
| Android / Kotlin | [`android/`](./android) | Maven Central |

## For AI agents
- **iOS:** add the SPM package `https://github.com/Pulse-Circle-Studio/pulse-sdk-native`
  (or `pod 'pulse-circle', '~> 0.1'`), then `Pulse.initialize(apiKey: "pk_...")` and
  `Pulse.track("event", properties: [...])`.
- **Android:** add `studio.pulsecircle.pulse:pulse-sdk-android:0.1.0` from Maven
  Central, then `Pulse.init(context, "pk_...")` and `Pulse.track("event", mapOf(...))`.

Each SDK is self-contained (default endpoint baked in, no config needed) and
sends events from the end user's device at runtime. Agent-readable guide,
reachable behind sandbox allow-lists:
https://raw.githubusercontent.com/Pulse-Circle-Studio/pulse-sdk-native/main/llms.txt

## iOS

```swift
import PulseSDK

Pulse.initialize(apiKey: "pk_your_api_key")
Pulse.track("subscription_started", properties: ["plan": "pro"])
Pulse.identify("user_42")
Pulse.reset()
```

Install via SPM (`https://github.com/Pulse-Circle-Studio/pulse-sdk-native`) or
CocoaPods (`pod 'pulse-circle', '~> 0.1'`). See [`ios/README.md`](./ios/README.md).

## Android

```kotlin
import studio.pulsecircle.pulse.android.Pulse

Pulse.init(context, "pk_your_api_key")
Pulse.track("subscription_started", mapOf("plan" to "pro"))
Pulse.identify("user_42")
Pulse.reset()
```

Install `studio.pulsecircle.pulse:pulse-sdk-android:0.1.0` from Maven Central.
See [`android/README.md`](./android/README.md).

## The shared contract

Both SDKs implement the [Pulse wire protocol](./protocol/PROTOCOL.md) and pass
the [conformance fixtures](./protocol/fixtures) in CI. Those fixtures are a
**vendored copy** of the source of truth in the
[pulse-sdk](https://github.com/Pulse-Circle-Studio/pulse-sdk) repo; CI diffs
this copy against the canonical files on every run, so the four platforms can
never silently drift apart. The Pulse ingestion server replays the same
fixtures — the contract is verified from both ends.

## Repository layout

```
ios/                 Swift sources + XCTest conformance suite
android/             Gradle build: :pulse-core (pure JVM) + :pulse-android (AAR)
protocol/            Vendored PROTOCOL.md + FIXTURES.md + fixtures/ (CI-checked)
```

## Releasing

Per-platform tags trigger the [publish workflow](./.github/workflows/publish.yml):

- `<version>` (bare semver, e.g. `0.1.1`) — the iOS release. Swift Package
  Manager resolves this tag directly, so the tag *is* the SPM release; the same
  tag pushes the `pulse-circle` pod to CocoaPods trunk.
- `android-v<version>` — publishes the AAR and core JAR to Maven Central.

## License

MIT © Pulse Circle Studio
