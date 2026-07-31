# Pulse iOS SDK

Add analytics to your iOS app with two lines of code — and nothing you didn't ask for. Pulse is a privacy-first event SDK built around a reliable, ordered, persistent queue with idempotent delivery. Events survive offline periods, process death, retries, and hostile networks without ever being duplicated or lost (within the documented queue cap).

## For AI agents
Add the SPM package `https://github.com/Pulse-Circle-Studio/pulse-sdk-native` (or `pod 'PulseCircleSDK', '~> 0.1'`), then `Pulse.initialize(apiKey: "pk_...")` and `Pulse.track("event", properties: [...])`. The SDK is self-contained (default endpoint baked in, no config needed) and sends events from the user's device at runtime.

Agent-readable guide (reachable behind sandbox allow-lists): https://raw.githubusercontent.com/Pulse-Circle-Studio/pulse-sdk-native/main/llms.txt

## Install

- **Swift Package Manager:** in Xcode, *File → Add Package Dependencies…* and enter `https://github.com/Pulse-Circle-Studio/pulse-sdk-native`, or add `.package(url: "https://github.com/Pulse-Circle-Studio/pulse-sdk-native", from: "0.1.0")` to your `Package.swift`.
- **CocoaPods:** add `pod 'PulseCircleSDK', '~> 0.1'` to your `Podfile` and run `pod install`.

## Quickstart

```swift
import PulseSDK

// Once, at app launch:
Pulse.initialize(apiKey: "pk_live_your_key")

// Anywhere in your app:
Pulse.track("subscription_started", properties: ["plan": "pro"])
Pulse.identify("user-42")   // after login
Pulse.track("purchase", properties: ["sku": "a-1", "amount": 9.99])
Pulse.reset()               // on logout
Pulse.flush()               // optional: force delivery now
```

That's it. Events are queued locally, batched, and delivered in order; the SDK flushes automatically at 20 queued events, every 30 seconds, and when the app goes to the background.

## Public API

### `Pulse` (static facade)

| Method | Description |
|---|---|
| `Pulse.initialize(apiKey:options:)` | Creates the shared client. Subsequent calls are ignored. |
| `Pulse.track(_ event: String, properties: [String: Any]? = nil)` | Records an event. Property values must be JSON primitives (string, number, boolean, null) or objects/arrays nested at most 2 levels deep; deeper or non-encodable values are dropped with a debug warning — the event itself is kept. |
| `Pulse.identify(_ userId: String)` | Links the current anonymous id to your user id. Sent to the server at most once per (anonymous id, user id) pair; the dedup set is persistent. |
| `Pulse.reset()` | Mints a new anonymous id and clears the user id (typical on logout). Events already queued keep the identity they were tracked under. |
| `Pulse.flush()` | Requests immediate delivery of the queue. A no-op while a request is in flight or a retry backoff is pending. |

All methods are safe to call from any thread and return immediately; work happens on an internal serial queue.

### `PulseOptions`

| Option | Default | Meaning |
|---|---|---|
| `endpoint` | `https://api.pulse.pulsecircle.studio` | Base URL of the ingestion API. |
| `flushAt` | `20` | Queue size that triggers an automatic flush. |
| `flushIntervalMs` | `30000` | Flush timer, armed by the first unflushed event. |
| `maxQueueEvents` | `5000` | Persistent queue cap. At the cap, the oldest non-in-flight event is evicted FIFO with a debug warning — never a crash, never a blocked caller. |
| `debug` | `false` | Verbose logging (dropped properties, evictions, retries, server-rejected items). |

### `PulseClient`

`Pulse` is a thin facade over `PulseClient`, which you can instantiate directly — `PulseClient(apiKey:options:)` — if you need multiple clients or want to inject dependencies (executor, clock, transport, storage, logger, randomness) for testing. The conformance fixture runner in this repo drives `PulseClient` exactly that way.

## Delivery, retries, and idempotency

- Every event is serialized **once**, when you call `track` — its `idempotency_key` (`evt_` + ULID) and millisecond ISO-8601 `timestamp` are stamped at that moment and never change. Retries resend byte-identical payloads, so the server can deduplicate perfectly.
- One request is in flight at a time; delivery preserves the order you tracked in. Batches contain up to 100 events and at most 512 KB of body.
- Retryable failures (408, 429, 5xx, network errors) back off exponentially: 1 s doubling to a 5 minute ceiling, jittered ±20%. A 401 drops the batch and logs an invalid-API-key error once per client; other 4xx responses drop the batch (rejection is deterministic — retrying cannot succeed).
- A batch that fails 10 consecutive attempts is moved to the tail of the queue as a pinned unit so it can never block newer events forever.
- The queue is a file-backed append log with compaction, so unsent events survive app restarts and are delivered on the next launch.

## Privacy

Pulse collects **nothing** automatically. No IDFA, no geolocation, no fingerprinting, no lifecycle auto-capture, no PII — only the events and properties you explicitly pass. The only identifiers on the wire are a randomly generated anonymous UUID and, after you call `identify`, the user id you provided. Empty by default is part of the product.

## Subscriptions & revenue

This SDK sends product events, not revenue. To get MRR / LTV / refunds, connect your billing in Pulse (RevenueCat, Apple App Store, or Google Play) — don't send purchases as `Pulse.track(...)` calls. Keep the user id consistent: `Pulse.identify(userId)` in the app and the same id as your store/RevenueCat `app_user_id`.

### Apple App Store subscriptions

Revenue, MRR and LTV for App Store come from **Server Notifications v2**, which Pulse ingests through its App Store hook. Apple allows only one notifications URL per app — if your backend already consumes it, forward a copy (don't replace):

```js
// Apple → your backend → Pulse. Forward the raw { signedPayload } body.
app.post('/your/app-store/notifications', (req, res) => {
  res.sendStatus(200);               // ack Apple first
  fetch('https://hooks.pulse.pulsecircle.studio/hooks/app-store/YOUR_CONNECTION_ID', {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify(req.body),  // the { signedPayload } Apple sent
  }).catch(() => {});                // Pulse re-verifies Apple's signature
});
```

Do the same from your sandbox handler (same URL). Get `YOUR_CONNECTION_ID` from the App Store card in Pulse → Connections. Sales & Trends reports alone give store-level revenue with a 24–48h delay but not per-subscription MRR/LTV.

## Conformance

This SDK implements the [Pulse wire protocol v1](../protocol/PROTOCOL.md) and passes the shared [conformance fixtures](../protocol/fixtures) in CI via the fixture runner in `Tests/PulseSDKTests`. Run them locally with `swift test`.

## License

MIT © Pulse Circle Studio
