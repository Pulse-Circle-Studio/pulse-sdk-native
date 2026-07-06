# Pulse Android SDK

Add analytics to your Android app in two lines. A privacy-first event SDK
built on a reliable, ordered, persistent queue with idempotent delivery —
events survive offline periods, process death, and retries without ever being
duplicated or lost (within the documented queue cap).

- Kotlin, coroutines-friendly, **no dependencies beyond kotlinx-serialization**.
- minSdk 24. No WorkManager, no background services — a persistent file queue
  plus a flush on backgrounding is all it needs.
- Sends nothing automatically: no advertising id, no location, no
  fingerprinting.

## Install

Maven Central:

```kotlin
// build.gradle.kts
dependencies {
    implementation("studio.pulsecircle.pulse:pulse-sdk-android:0.1.0")
}
```

## Quickstart

```kotlin
import studio.pulsecircle.pulse.android.Pulse

// Once, e.g. in Application.onCreate():
Pulse.init(context, "pk_your_api_key")

// Anywhere:
Pulse.track("subscription_started", mapOf("plan" to "pro"))
Pulse.identify("user_42")   // after login
Pulse.reset()               // on logout
Pulse.flush()               // optional: force delivery now
```

Events are queued locally, batched, and delivered in order. The SDK flushes
automatically at 20 queued events, every 30 seconds, and when the app goes to
the background.

## API

| Method | Purpose |
|---|---|
| `Pulse.init(context, apiKey, options?)` | Configure once. Idempotent — later calls are ignored. |
| `Pulse.track(event, properties?)` | Queue an event. Properties: primitives, nested ≤ 2 levels. |
| `Pulse.identify(userId)` | Associate the identity with a user id (sent once per pair). |
| `Pulse.reset()` | Log out: new anonymous id; queued events keep the old identity. |
| `Pulse.flush()` | Force-send the queue. |

`PulseOptions` fields: `endpoint`, `flushAt` (default 20), `flushIntervalMs`
(default 30 000), `maxQueueEvents` (default 5 000), `debug`.

## How delivery works

- `idempotency_key` and `timestamp` are fixed when you call `track`; retries
  resend them unchanged, so a flaky network never duplicates events.
- The queue is a file-backed append log with compaction under the app's
  internal storage (cap 5,000 events; oldest evicted first past the cap),
  delivered in order.
- Failed batches retry with exponential backoff and jitter; a persistently
  rejected batch is set aside after 10 attempts so it never blocks the queue.
- All public methods are safe to call from any thread — internally everything
  runs on a single serial executor.

## Module layout

- **`pulse-sdk-core`** — pure Kotlin/JVM engine (queue, batching, retry,
  identity, transport). Testable without an Android device; all logic and the
  conformance-fixture suite live here.
- **`pulse-sdk-android`** — a thin Android wrapper: SharedPreferences
  identity, file queue under `filesDir`, and an activity-lifecycle
  background-flush hook.

## Building and testing

```bash
cd android
./gradlew :pulse-core:test            # conformance fixtures + unit tests (JVM)
./gradlew :pulse-android:assembleRelease
```

`:pulse-core` builds anywhere with a JDK. `:pulse-android` requires the
Android SDK (`ANDROID_HOME`); the Gradle settings include it only when an SDK
is present, so `:pulse-core` remains buildable on machines without one.

## Releasing

Bump `version` in the module `build.gradle.kts` files, then push an
`android-v<version>` tag. The publish workflow runs the tests and publishes
both artifacts to Maven Central via Sonatype (signing and credentials come
from repository secrets).

## License

MIT © Pulse Circle Studio
