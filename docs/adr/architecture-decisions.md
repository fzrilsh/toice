# Architecture Decision Records — Toice

Toice (Tour + Voice) — offline peer-to-peer voice intercom for motorcycle touring convoys. No internet or cellular dependency for the core communication feature. Target group size: 5-7 riders. Typical operating speed: 60-80 km/h, convoy spacing 10-15m under normal conditions.

---

## ADR-001: Network topology — hotspot-hosted star, not mesh

**Status:** Accepted

**Context**

The app must connect Android and iOS devices without internet, at riding speed, with a group of 5-7 riders. Four topologies were evaluated: WiFi Direct / WiFi Aware (NAN), Bluetooth Low Energy mesh, a single-hotspot star, and dedicated mesh radio hardware (ESP32/LoRa class).

**Decision**

Use a single-hotspot star topology. One device hosts a local-only WiFi hotspot (no internet uplink required); all other devices join it as regular WiFi clients. The host role is not fixed to one device — see ADR-003.

**Rejected alternatives**

- **WiFi Direct / WiFi Aware.** Not usable cross-platform. iOS does not expose WiFi Direct or NAN to third-party apps; the only peer-to-peer framework Apple exposes is `MultipeerConnectivity`, which is proprietary and only interoperates between Apple devices. Any WiFi Direct design silently excludes every iOS rider.
- **BLE mesh.** Cross-platform, but bandwidth is insufficient for full-duplex voice at usable quality. Viable only for control/telemetry (status pings, position), not for the primary audio path, unless dropping to heavily compressed vocoders (e.g. Codec2 at 700-3200bps) with correspondingly poor quality.
- **Concurrent AP + WiFi Direct hybrid** (Android nodes mesh via WiFi Direct, one Android node bridges to a hotspot for iOS riders). Rejected: requires a single device to run SoftAP and WiFi Direct client/group-owner roles simultaneously while bridging traffic between them. Support for this concurrent mode is chipset-dependent (varies across Qualcomm/MediaTek/other vendors) and not reliable enough for a product targeting mixed, unknown hardware.
- **Dedicated mesh hardware** (ESP32/nRF24/LoRa relay per rider). Technically the most robust option (true multi-hop mesh, no OS networking restrictions, tunable RF range) but rejected on cost grounds: the product goal is to minimize cost and avoid requiring riders to buy or carry extra hardware. May be revisited later as a premium/hardware tier, not for MVP.

**Consequences**

- Single point of failure inherent to star topology is mitigated by continuous host re-election (ADR-003), not eliminated.
- Effective radio range is bounded by consumer WiFi hotspot range (realistically ~20-30m in open outdoor conditions, less with obstruction), which sets the practical ceiling on convoy spacing this system tolerates without dropouts.
- Group size is capped at 5-7 riders by design. Splitting into multiple independent sub-groups was considered and explicitly rejected by product decision — the app is scoped to be effective for 5-7 motorcycles, not designed to scale beyond that via sharding.

---

## ADR-002: Cross-platform bootstrap and auto-reconnect

**Status:** Accepted

**Context**

iOS requires explicit user consent to join a WiFi network the first time, and does not allow apps to silently create a hotspot. A repeatable mechanism is needed to (a) form the initial group and (b) let every subsequent host handoff (ADR-003) reconnect all clients without manual intervention.

**Decision**

- **Bootstrap:** one rider creates the group in-app. This generates a fixed SSID, password, and group ID, and immediately starts the hotspot on that device (first host). A QR code encoding SSID + password + group ID (+ a nonce) is displayed. Every other rider scans it once, before departure.
- **iOS join:** via `NEHotspotConfiguration`, passing SSID + password programmatically. User approves a system prompt once, at scan time.
- **Android join / host:** via a custom `SoftApConfiguration` (not the OS default `startLocalOnlyHotspot`, which generates a random SSID/password per session).
- **Fixed credentials for the life of the trip.** The SSID and password generated at bootstrap are reused for every subsequent host, regardless of which physical device is hosting. From iOS's perspective this is always "a known network," so `NEHotspotConfiguration` auto-rejoins without a new prompt on every handoff.

**Consequences**

- QR scan is a one-time action per trip/session, not per handoff.
- All devices must persist the group credentials locally for the session (cleared at trip end / explicit group teardown).
- Anyone who captures the QR code (photo, screenshot) could join the hotspot for that session. Acceptable risk for MVP; flagged as a hardening item (rotating nonce validation, or app-layer authentication over the data channel) for later.

**Addendum (Phase 0, 2026-08-11): platform reality vs the original decision.**

- **Android host:** the public `WifiManager.startLocalOnlyHotspot(callback, handler)` always generates a random SSID/password, which breaks fixed credentials. The overload taking a `SoftApConfiguration` is a hidden `@SystemApi` requiring `NETWORK_SETTINGS` (system apps) or `NEARBY_WIFI_DEVICES` (API 33+). We reach it by reflection on API 33+ with `NEARBY_WIFI_DEVICES` granted. Any failure (missing hidden API, OEM block, `SecurityException`, older API) degrades to a manual fallback: the app shows the credentials and the QR, the user creates the hotspot by hand in Settings. `startHost` returns `HostStartMode.programmatic` or `manualRequired` to drive this. The fixed-credential goal is unchanged; only the mechanism now has two tiers.
- **iOS join:** `NEHotspotConfiguration` is dropped. Its entitlement (`com.apple.developer.networking.HotspotConfiguration`) is gated behind the paid Apple Developer Program, and leaving it in the plist breaks free-provisioning signing. Instead the host renders a standard `WIFI:S:<ssid>;T:WPA;P:<password>;;` QR, which the native iOS Camera (iOS 11+) and Android Camera (9+) decode into the system join flow. The user taps Join once; the network is then a known network, so auto-rejoin across handoffs works exactly as this ADR intends. mDNS/Bonjour discovery of the host IP needs no entitlement (only raw multicast sockets do), so `NSLocalNetworkUsageDescription` + `NSBonjourServices` suffice.
- If a paid account is later obtained, `NEHotspotConfiguration` can be added as a smoother in-app join path without changing the credential format or the QR.

---

## ADR-003: Dynamic host election and handoff

**Status:** Accepted

**Context**

The hosting device changes over the course of a trip, both to spread battery/thermal load and to keep the host physically central to the group as convoy position shifts. Any device should be eligible to host, not just a fixed backup.

**Decision**

- **Fitness score, not threshold gating.** Every device computes a composite score from three normalized (0-100) components: RSSI centrality, battery level, thermal state.
  ```
  score = (w1 * rssi_score) + (w2 * battery_score) + (w3 * thermal_score)
  ```
  - `rssi_score`: derived from the *minimum* RSSI to the farthest peer (worst-case link), not an average — the host must stay reachable by everyone, not just be well-connected on average.
  - `battery_score`: battery percentage, curved to penalize sharply below ~30%.
  - `thermal_score`: from OS thermal state (`ProcessInfo.thermalState` on iOS, `PowerManager.getCurrentThermalStatus()` on Android), penalized heavily from "serious" upward.
  - No component is a hard cutoff. A device in poor thermal state can still be selected if every other candidate is worse.
  - Initial weighting: RSSI weighted highest (it directly affects connectivity for everyone), battery and thermal weighted lower (longevity concerns). Weights are tunable and must be validated empirically during testing.
- **Broadcast interval:** each device broadcasts its RSSI vector (RSSI to every peer) over the existing data channel every 10-15 seconds under stable conditions, matching observed real-world convoy spacing consistency. An out-of-cycle broadcast fires immediately if a device detects its RSSI to any peer drop past a defined threshold (e.g. >10dBm drop) — event-triggered, not purely periodic.
- **Election is deterministic and shared.** All devices compute the same score from the same broadcast data, so all devices independently arrive at the same ranking.
- **Hysteresis before switching.** A new candidate must beat the current host's score by a minimum margin, sustained for a minimum duration, before a handoff is triggered. Prevents flapping from transient RSSI noise.
- **Explicit handoff protocol, not silent switch.** The winning candidate broadcasts handoff intent to the group and waits for acknowledgment from all members before the current host tears down its AP and the new host brings its AP up (same fixed SSID/password from ADR-002). Unilateral takeover (no wait for ack) is only permitted when the current host is unresponsive past a timeout (crash / out of range), not as the normal path.

**Consequences**

- Prevents split-brain (two devices independently deciding to become host and running simultaneous APs).
- Adds one extra round trip (intent + ack) to every voluntary handoff, trading a small latency cost for safety against dual-AP states.
- Requires every device to continuously run the same election logic in the background, which must itself survive OS background suspension (see ADR-005).

**Addendum (Phase 0, 2026-08-11): iOS cannot host, so it is excluded from election.**

- "Any device should be eligible to host" holds only for Android. iOS gives third-party apps no way to bring up an access point (there is no public or entitlement-gated API for it, and none is expected). An iPhone can only ever be a client on this network.
- Election therefore treats iOS devices as host-ineligible: they broadcast their RSSI vector and participate in scoring so an Android host stays central to them, but they are never selected as the handoff target.
- Every group needs at least one Android device to host. An all-iPhone convoy cannot be served and is out of scope. This is surfaced at group creation (Phase 4), not silently.
- Follows directly from the ADR-002 addendum: dropping `NEHotspotConfiguration` removes in-app join on iOS, and iOS never had an in-app host path to begin with.

---

## ADR-004: Audio transport and mixing

**Status:** Accepted

**Context**

Full-duplex, always-on voice ("like a phone call," not push-to-talk) across 5-7 riders, over the local network formed in ADR-001, using device microphones/BT or wired headsets in noisy outdoor conditions.

**Decision**

- **Transport:** WebRTC (`flutter_webrtc`), using local-network ICE candidates only — no STUN/TURN needed since all peers share one LAN via the hotspot. WebRTC's built-in Opus codec, echo cancellation, noise suppression, AGC, and jitter buffer are used rather than building custom DSP.
- **Topology:** host-side mixing, not full mesh. The host receives all individual streams, mixes them, and broadcasts one combined stream back out. Rejected full mesh (every device holds N-1 direct peer connections) because per-device encode/decode load scales with group size and is heavier on battery-constrained devices; centralizing mixing on the host gives more predictable, bounded resource usage across the group. This trades host CPU load for client simplicity — to be validated against ADR-003's host election under real device load during testing.
- **Silence handling:** Opus DTX (Discontinuous Transmission) enabled. Given real-world observation that riders are silent most of the trip and only communicate for obstacles or route changes, DTX substantially cuts radio duty cycle (and therefore heat/battery draw) versus continuous transmission.
- **Speaker priority (ducking):** loudest-speaker-wins, using WebRTC's per-track audio level metering (no custom VAD needed). The currently loudest stream is passed at full gain; other concurrent streams are attenuated (not muted) by roughly 15-20dB, with hysteresis/hold-time to avoid rapid switching between two similarly loud speakers.
- **Echo cancellation mode:** conditionally reduced when the device is confirmed on a headset (BT or wired) rather than device speaker+mic, since acoustic echo loop doesn't apply — lowers CPU load on the audio pipeline.

**Consequences**

- Host bears mixing CPU load in addition to hotspot radio load; thermal/CPU headroom should be folded into the ADR-003 fitness score once measured.
- DTX and headset-conditional AEC both require runtime detection (headset connection state) feeding into the WebRTC audio pipeline configuration.

---

## ADR-005: Background execution and power management

**Status:** Accepted

**Context**

The app must keep the hotspot, WebRTC session, and election logic alive while the phone screen is off or another app (e.g. GPS navigation) is in the foreground — both platforms aggressively suspend backgrounded apps.

**Decision**

- **Android:** foreground service with a persistent notification, exempted from battery optimization / Doze where required. Screen-off is the expected normal operating mode (mount stays cool; UI is not required to be visible during a call).
- **iOS:** background audio mode entitlement, structured so the app is treated as an active audio session even during silence (DTX periods), preventing the OS from treating the process as idle. Distinguish explicitly from audio session ducking (automatic, OS-level, happens when another app plays audio like turn-by-turn instructions) — ducking is a mixing concern, not a suspension concern, and does not by itself keep the process alive.
- **Recovery:** if the host process crashes (not just drops out of range), remaining devices must detect the failure via the ADR-003 timeout path and re-elect without manual restart. A device that crashes and reopens must auto-rejoin using cached group credentials, not require a fresh QR scan.
- **Bluetooth/WiFi coexistence:** both radios share the 2.4GHz band on-device. Coexistence quality is chipset-dependent; degradation (BT audio stutter/disconnect under sustained WiFi transmission) has been observed on older/lower-tier chipsets. No software mitigation is planned for MVP — instead, this becomes a documented minimum device/chipset requirement, with wired headset as a supported fallback for devices with poor coexistence.

**Consequences**

- Requires native platform code (not covered by common Flutter plugins) for foreground service and background audio/session management — see ADR-006.
- A minimum spec / compatibility list becomes a product requirement, not just an engineering nice-to-have, given BT/WiFi coexistence variance.

---

## ADR-006: Tech stack — Flutter with native platform channels, no backend for core feature

**Status:** Accepted

**Context**

Choice of app framework and whether the core voice feature needs a hosted backend.

**Decision**

- **Flutter (Dart)** for UI, state management, and all pure logic that doesn't touch OS-level APIs: election scoring (ADR-003), handoff state machine, audio priority logic, group/session state.
- **Native platform channels** (Swift/Kotlin) required for: hotspot creation/join (`NEHotspotConfiguration`, custom `SoftApConfiguration`), foreground service / background audio mode (ADR-005), and RSSI/battery/thermal sensor reads. These are not fully covered by existing Flutter plugins and must be hand-written.
- **`flutter_webrtc`** for the WebRTC layer (ADR-004) — mature plugin wrapping native libwebrtc on both platforms, no custom native work needed here.
- **No backend server for the core communication feature.** All voice/election/handoff traffic is device-to-device over the local hotspot LAN; there is nothing to host. This is a deliberate cost decision, not an oversight.
- **Backend is deferred and scoped separately**, only for features that are inherently online and asynchronous to the ride itself: accounts, trip history, offline route package distribution (see the offline turn-by-turn voice idea — explicitly deferred, not part of this architecture), analytics/crash reporting. These may use a lightweight/serverless backend later and must not block the core MVP.

**Consequences**

- "Flutter app" here means "Flutter + custom native plugin layer," not a pure-Dart app — plan native iOS/Android engineering effort accordingly, not just Dart.
- Because there's no backend for the core feature, most integration risk sits in native platform behavior (OS version differences, OEM restrictions), which is why platform-channel validation is sequenced first in the delivery plan (see `docs/CHANGELOG.md` phase plan in `CLAUDE.md`).

---

## Rejected scope (explicitly out of MVP)

- **Sub-grouping / multi-hop relay between sub-groups** for convoys larger than one hotspot can reliably cover. Rejected by product decision — the app is scoped to be effective for 5-7 motorcycles, full stop, not designed to shard into relayed sub-groups.
- **Dedicated hardware relay nodes** (ESP32/LoRa). Rejected on cost grounds (see ADR-001). May be reconsidered as a future hardware-assisted tier, not MVP.
- **Offline downloaded-route turn-by-turn voice guidance** ("500m lagi belok kiri"). Product idea, explicitly deferred — not part of this architecture. Worth revisiting later as a test case for the audio ducking behavior in ADR-004/ADR-005, but not a Phase 0-5 deliverable.