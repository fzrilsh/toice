# Changelog

All notable changes to Toice. See `docs/adr/architecture-decisions.md` for the
architecture this implements and `CLAUDE.md` for the delivery phase plan.

## Phase 4.5 - UX polish + app-layer Trip PIN auth (2026-08-15) ✅ (pure Dart)

Closes the Option-B gap Phase 4 left open (the credential secret was persisted
but never actually used to guard the session) and polishes the UI for real
riding conditions. Pure Dart/Flutter, unit- and widget-tested; still on the
mock voice session, so live audio remains Phase 6 and native hotspot remains
device-gated at Phase 5.

### Changed

- **`nonce` renamed to Trip PIN everywhere**, including the JSON key
  (`lib/group/group_credentials.dart`). Since this is an unreleased MVP there is
  no migration or backward-compatibility shim. The PIN is now a 4-6 digit
  numeric value a rider can read off a screen or type, not an opaque nonce.

### Added

- `lib/audio/auth.dart`: app-layer Trip PIN authentication over the signaling
  channel. Host issues a fresh random challenge; client answers with
  HMAC-SHA256(tripPin, challenge); host recomputes and admits only on a
  constant-time match. The PIN never crosses the wire, and each `PinChallenge`
  is single-use so a captured response cannot be replayed against a new
  challenge. `authenticateClient` / `respondToChallenge` drive it over the
  `Signaling` boundary.
- `lib/audio/signaling.dart`: `ChallengeMessage` / `AuthResponseMessage` on the
  sealed `SignalMessage`; `peer_link.dart` ignores a stray auth frame (the
  handshake runs before the link exists).
- `lib/audio/voice_session.dart`: `VoiceSession.host` takes an optional
  `tripPin`; `addPeer` runs the handshake first and throws
  `AuthFailedException` on a wrong PIN, so an unauthenticated peer never enters
  the roster. Client `connectToHost` answers the challenge.
- `lib/group/group_credentials.dart`: a PIN-only QR codec (`pinQrPayload` /
  `pinFromQr`, `TOICE-PIN:` prefix) for optional Android auto-fill, and
  `withTripPin` to fill a PIN onto WiFi-QR-derived credentials.
- `lib/ui/pin_entry_screen.dart`: numeric PIN entry shown after the client joins
  the WiFi. Android can scan the host's PIN-only QR to auto-fill; iOS types it
  (platform branch injected for testability). `create_screen.dart` shows the PIN
  large plus its QR; `home_screen.dart` routes join through PIN entry before the
  call.
- `lib/ui/theme.dart` + `lib/ui/app.dart`: high-contrast outdoor dark theme
  (near-black asphalt, white text, hi-vis amber primary, hazard-red destructive
  actions), oversized heavy type, 64px glove tap targets; dark by default.
- `lib/ui/transitions.dart`: `toiceRoute`, a shared fade+slide page transition
  that degrades to a plain fade under reduced motion. `home_screen.dart` empty
  state; join failures and permission denials now surface as a SnackBar instead
  of being swallowed.
- `crypto` pinned exact (3.0.7), promoted from transitive.
- Tests: HMAC determinism + challenge verify/reject/replay + handshake over
  loopback signaling (auth, 6), Trip PIN session gating (voice session, +1), PIN
  entry widget (3), theme (2), rename/PIN-codec updates across the group tests.
  Full suite green (115).

### Deviations from spec

- **App-layer auth is HMAC over the PIN, not a full PAKE.** A 4-6 digit PIN is
  low-entropy, so this resists passive capture and replay but not an active
  on-LAN attacker brute-forcing offline. Flagged with a `ponytail:` note in
  `auth.dart`; the upgrade path (SPAKE2/J-PAKE) keeps the same two-message
  shape. Acceptable for the MVP threat model (a bystander who merely scanned the
  WiFi QR should not be admitted to the call).
- **Trip PIN stays out of the WiFi QR (Option B, unchanged from Phase 4).** The
  join QR remains a strictly standard `WIFI:` string; the PIN is delivered
  out-of-band (shown large on the host, optionally as a separate `TOICE-PIN:`
  QR) and entered on the client.

## Phase 4 - QR bootstrap + full UI (2026-08-12) ✅ (pure Dart)

The trip bootstrap (ADR-002) and the real screens that replace the Phase 0 PoC,
as pure, unit- and widget-tested Dart/Flutter. No hardware: the QR codec,
persistence, and trip lifecycle are all tested without a device; the in-app
camera scan itself is exercised on hardware at Phase 5.

### Added

- `lib/group/group_credentials.dart`: a persisted `nonce` (generated from the
  same secure RNG), `fromWifiQrPayload` to parse a scanned standard `WIFI:`
  string back into credentials (groupId from the `Toice-` SSID prefix, throws
  on a malformed or non-Toice payload), and `toJson`/`fromJson`.
- `lib/group/credential_store.dart`: `CredentialStore` (`shared_preferences`,
  pinned exact), one JSON blob under one key, save/load/clear for the
  trip-lifetime credentials. A corrupt blob loads as null, never crashing
  launch.
- `lib/group/group_controller.dart`: `GroupController` (`ChangeNotifier`, no new
  dep) owning the active credentials + role, with create/joinWith/restore/
  endTrip. `restore` auto-loads a persisted trip on relaunch so a mid-ride
  restart rejoins without re-scanning.
- `lib/ui/scan_screen.dart`: `ScanScreen` (`mobile_scanner`, pinned exact, +
  `CAMERA` permission). Android scans the host's QR in-app and pops parsed
  credentials; iOS gets manual SSID/password entry as the in-app fallback (it
  joins via the system Camera). Platform branch is injected for testability.
- `lib/ui/create_screen.dart`: host screen showing the QR + big SSID/password
  text, absorbing the Phase 0 native start + manual-fallback path.
- `lib/ui/home_screen.dart`: reworked from the Phase 0 PoC into a Create/Join
  landing that auto-restores a persisted trip and shows an active-trip banner
  with End trip.
- Tests: credential codec (+5), credential store (5), group controller (5),
  scan screen (3), reworked home-screen nav/restore (3). Full suite green (102).

### Deviations from spec

- **Nonce is not in the QR (Option B).** ADR-002 lists a nonce in the QR, but
  the addendum requires the join QR to stay a strictly standard `WIFI:` string
  the iOS/Android system Camera parses. A non-standard tag risks a silent parse
  failure there, so the nonce is generated and persisted (rides in
  `toJson`/`fromJson`) but left out of `toWifiQrPayload`. A scanned join starts
  with an empty nonce; app-layer auth using it over the data channel is a later
  hardening phase.
- Screens still open the mock voice session; real audio (mic, host-side mixing,
  live tracks) is Phase 6. Native hotspot start/join is wired but device-gated
  (Phase 5).

## Phase 3 - Audio priority + state management (2026-08-11) ✅ (pure Dart)

The audio decision layer (ADR-004) and the app state that binds it, as pure,
unit-tested Dart. No hardware: ducking runs on plain level numbers, metering is
a mock stream, and the state store folds it together for the UI. Host-side
mixing and real Opus/DTX on live tracks are Phase 6.

### Added

- `lib/audio/ducking.dart`: `DuckingEngine`, loudest-speaker-wins. Maps
  per-stream level snapshots (dBFS) to gain decisions (active 0 dB, others
  -18 dB), with hold-time hysteresis so two similar speakers don't thrash and an
  activation floor so ambient noise never grabs "active". Pure numbers, no
  `flutter_webrtc`.
- `lib/audio/speaker_levels.dart`: `SpeakerLevelSource` metering boundary
  (WebRTC stats poller on device, `MockSpeakerLevelSource` in tests) +
  `ActiveSpeakerTracker` that folds frames through the engine and republishes
  `activeSpeaker` (deduped) and per-peer `gains` streams.
- `lib/audio/audio_config.dart`: `AudioPipelineConfig.forRoute`, DTX always on,
  AEC on for the device speaker and off for headsets (no acoustic loop, saves
  CPU).
- `lib/app/session_store.dart` (new top-level `lib/app/`): `SessionStore`
  (`ChangeNotifier`, no new dep), one source of truth binding connection state,
  active speaker, and mirrored host/handoff status into a `List<RiderView>`.
- `lib/ui/call_screen.dart`: roster now renders from `SessionStore` with a live
  speaking indicator and host marker; mock harness gains a scripted speaker
  source.
- Tests: ducking (8), speaker levels (4), audio config (3), session store (4),
  plus an updated call-screen speaking-indicator widget test. Full suite green.

### Deviations from spec

- Decision layer only. Metering (`SpeakerLevelSource`) and applying the gain map
  / DTX / AEC config to real tracks are interfaces here; the WebRTC stats poller,
  host-side mixing, and live media are deferred to Phase 6. The priority and
  config *decisions* are proven; the media path is not.

## Phase 2 - Election scoring + handoff FSM (2026-08-11) ✅ (pure Dart)

The full host-election pipeline (ADR-003) as pure, unit-tested Dart. No
hardware: the daemon runs over a mock channel and an injected clock, so the
whole loop is deterministic under `flutter test`. The data channel and native
AP swap it drives are Phase 6/7.

### Added

- `lib/election/broadcast.dart`: `ElectionBroadcast` wire model (sender, RSSI
  vector, battery, thermal, `hostCapable`, timestamp) + JSON codec.
  `RssiVector.worstDbm` returns the weakest link so a candidate is scored on its
  worst peer (ADR-003). `rssiScoreFromDbm` / `thermalScoreFromState` mappers.
- `lib/election/ranking.dart`: `rankCandidates` composites fitness over
  `fitness_score.dart` and sorts best-first, excluding non-host-capable (iOS)
  and blind (no-link) devices; ties break by deviceId so ranking is total and
  identical across devices with no shared clock.
- `lib/election/hysteresis.dart`: `HysteresisGate`, margin + sustained-duration
  anti-flap. A lapse resets the timer; a new challenger restarts its window.
- `lib/election/handoff.dart`: `HandoffMachine`, `stable -> awaitingAcks ->
  switching -> stable` with ack-timeout unilateral takeover. `performSwitch`
  fires exactly once (single-host invariant, ADR-001); emits actions, never
  touches the radio.
- `lib/election/election_daemon.dart`: `ElectionDaemon` ties it together over
  `ElectionChannel` + `HostSwitcher` abstractions, pruning stale peers, ranking,
  gating, and driving the handoff on a win. Advanced by explicit `tick()`.
- Tests: broadcast (9), ranking (6), hysteresis (7), handoff (7), daemon (6).
  Full suite green (62 total).

### Deviations from spec

- Logic only. The `ElectionChannel` (data channel over the hotspot) and
  `HostSwitcher` (native AP start/stop) are interfaces here; their real
  implementations and on-device validation of actual handoff timing are deferred
  to Phases 6/7. The election math and protocol are proven; the transport is
  not.

## Roadmap reorder (2026-08-11)

No physical Android devices are available, so the phase order is changed to
front-load pure-Dart/Flutter work and defer everything that needs hardware.
This proves logic, not the product: the fixed-credential hotspot + handoff on
real iOS/Android OEMs stays unvalidated until Phase 5. Full detail in
`CLAUDE.md`.

- Pure-Dart, next: Phase 2 (election scoring + handoff FSM), Phase 3 (audio
  priority logic + state management), Phase 4 (QR bootstrap + full UI).
- Hardware-gated, deferred: Phase 5 (Phase 0/0b device validation), Phase 6
  (real WebRTC audio + host-side mixing), Phase 7 (background execution),
  Phase 8 (battery/thermal + native sensors).

## Phase 1 - WebRTC session, mock-track (2026-08-11) ✅ (code complete, device validation deferred to Phase 6)

WebRTC negotiation layer and a call screen bound to live connection state, built
behind a transport boundary so the logic runs under `flutter test` without a
device. Real audio (mic capture, host-side mixing, on-LAN ICE) is deferred to
Phase 6.

### Added

- `lib/audio/signaling.dart`: SDP/ICE message types and a bidirectional
  `Signaling` channel (on-device socket in Phase 6, loopback in tests).
- `lib/audio/rtc_peer.dart`: `RtcPeer`, the narrow slice of `RTCPeerConnection`
  the session needs (negotiation + connection state), plus a factory typedef.
- `lib/audio/peer_link.dart`: per-link SDP offer/answer + ICE trickle state
  machine. Client offers, host answers (star topology, ADR-001).
- `lib/audio/voice_session.dart`: host (one link per client) vs client (single
  link to host) roles, `connectionChanges` broadcast stream, teardown.
- `lib/audio/webrtc_peer.dart`: device-backed `RtcPeer` wrapping
  `flutter_webrtc`, local-network ICE only (no STUN/TURN). ponytail: negotiation
  only, no mic capture or host-side mixing yet.
- `lib/ui/call_screen.dart`: call UI rendering live per-peer connection state,
  session + signaling injected, with a mock harness (scripted peer, null
  signaling) so it runs and widget-tests without libwebrtc.
- `home_screen` routes into `CallScreen` for host and client roles.
- Dep (pinned exact): `flutter_webrtc: 1.1.0`.
- Tests: 9 audio (loopback signaling + fake peers), 2 call-screen widget tests,
  1 navigation test. Full suite green (27 total).

### Deviations from spec

- This is the mock-track only. ADR-004 real audio (transport over the hotspot
  LAN, Opus DTX, loudest-speaker ducking, host-side mixing) is intentionally
  deferred to Phase 6 because it needs hardware. The state machine is proven;
  the media path is not.

## Next

**Phase 5 - Phase 0/0b device validation.** Hardware-gated, deferred until
Android devices are back. Run `docs/PHASE0-DEVICE-CHECKLIST.md` on 2 Android
(gate: same-credential rejoin + handoff simulation), then an iPhone client.
This is the real product-risk gate: the fixed-credential hotspot and handoff on
real iOS/Android OEMs stays unvalidated until it passes, and everything in
Phases 0-4 assumes it does. Add a checklist item confirming the system Camera
joins from the standard `WIFI:` QR with no nonce tag (Option B).

## Phase 0 - Platform channel PoC (2026-08-11) ✅ (code complete, device validation pending)

Made the fixed-credential hotspot bridge real: Android host (reflection) + Android
client join, with a manual fallback and a QR-based iOS join path. Code is done and
the APK builds; on-device validation (2 Android + iPhone) is a manual step tracked in
`docs/PHASE0-DEVICE-CHECKLIST.md`.

### Added

- `lib/group/group_credentials.dart` + `test/group/group_credentials_test.dart`:
  `GroupCredentials.generate()` produces a fixed SSID (`Toice-XXXXXXXX`, 14 bytes),
  16-char WPA2 password, and `toWifiQrPayload()` -> `WIFI:S:<ssid>;T:WPA;P:<pass>;;`.
  Crockford base32 (no `I/L/O/U`, no `WIFI:`-reserved chars), so the QR needs no
  escaping. 7 unit tests cover bounds, charset, uniqueness, seeded determinism, and
  the escaping guard.
- `android/.../SoftApReflection.kt`: reflects `SoftApConfiguration.Builder` and the
  hidden `startLocalOnlyHotspot(SoftApConfiguration, Executor, callback)` to set fixed
  credentials (API 33+ with `NEARBY_WIFI_DEVICES`).
- `lib/group/permissions.dart`: runtime gating (`nearbyWifiDevices` on 33+, location on
  <=32); no-op true on iOS.
- `lib/ui/home_screen.dart`: Phase 0 PoC screen. Host (QR + big SSID/password text +
  manual-fallback instructions and Settings deep-link), Join (manual SSID/password),
  and a live log of calls and `HotspotEvents`.
- Deps (pinned exact): `permission_handler: 11.3.1`, `qr_flutter: 4.1.0`.

### Changed

- `pigeons/native_bridge.dart`: `startHost` now returns `HostStartMode`
  (`programmatic` | `manualRequired`); added `openTetherSettings()` and a
  `HotspotEvents` `@FlutterApi` (`onHostStopped`, `onClientStateChanged`). Regenerated
  the three `.g` bindings.
- `android/.../HotspotHandler.kt`: real `startHost` (reflection then manual fallback,
  never throws on the fallback path), `stopHost`, `openTetherSettings` deep-link, and
  `joinAsClient`/`leave` via `WifiNetworkSpecifier` + `requestNetwork` +
  `bindProcessToNetwork` (API 29+).
- `android/app/build.gradle.kts`: `minSdk` 26 -> 29 (single supported client-join path).
- `AndroidManifest.xml`: `ACCESS_FINE_LOCATION` capped at `maxSdkVersion=32`.

### Deviations from spec

- **iOS drops `NEHotspotConfiguration`** (ADR-002 addendum). Its entitlement is behind
  the paid Apple Developer Program and breaks free-provisioning signing, so it was
  removed (`Runner.entitlements` deleted, `CODE_SIGN_ENTITLEMENTS` cleared from
  `project.pbxproj`). iOS joins by scanning the standard `WIFI:` QR with the system
  Camera instead. Credential format is unchanged, so a paid account could add the
  in-app path later without rework.
- **Android host is reflection + manual fallback**, not a plain `SoftApConfiguration`
  call (ADR-002 addendum): the public API cannot set credentials and the hidden overload
  needs API 33+. Below that, or on any OEM block, the user creates the hotspot manually.
- **iOS is excluded from host election** (ADR-003 addendum): it cannot host an AP, so
  every group needs at least one Android and all-iPhone convoys are out of scope.

## Scaffold (2026-08-11)

Project bootstrap. Structure and native bridge signatures only, no on-device
feature validation yet (that is Phase 0).

### Added

- Flutter project (`flutter create`, Android + iOS only), bundle id
  `com.fzrilsh.toice`, Kotlin + Swift native language.
- `lib/` structure per CLAUDE.md: `election/`, `audio/`, `native_bridge/`,
  `group/`, `ui/`. Minimal `main.dart` -> `ui/app.dart` -> `ui/home_screen.dart`.
- `lib/election/fitness_score.dart`: pure ADR-003 composite scoring
  (`computeFitnessScore`, `batteryScoreFromPercent`, `FitnessWeights`) with
  unit tests in `test/election/fitness_score_test.dart`. Scoring primitive
  only, no broadcast/hysteresis/handoff state machine (Phase 2).
- Pigeon platform channel definitions (`pigeons/native_bridge.dart`) for the
  three native APIs (ADR-006): `HotspotApi`, `SensorApi`, `BackgroundApi`, plus
  `HotspotCredentials` and `ThermalState`. Generated bindings:
  `lib/native_bridge/native_bridge.g.dart`, Kotlin `NativeBridge.g.kt`,
  Swift `NativeBridge.g.swift`.
- Native stubs (Kotlin + Swift handlers) wired up in `MainActivity.kt` /
  `AppDelegate.swift`. Every method fails loudly ("not implemented (Phase 0)"),
  never returns a dummy value.
- Manifest/plist/entitlements prepared declaratively: Android permissions
  (hotspot, WiFi state, `NEARBY_WIFI_DEVICES`, mic, foreground service,
  notifications), iOS usage descriptions + `UIBackgroundModes: audio` +
  `com.apple.developer.networking.HotspotConfiguration` entitlement.
- `.gitignore`, `lefthook.yml` (pre-commit format+analyze, pre-push test),
  FVM pin (`.fvmrc`).

### Deviations from spec

- FVM added for Flutter version pinning (not mentioned in CLAUDE.md). All
  build/test commands run via `fvm flutter` / `fvm dart`.
- Android `minSdk` raised to 26 (`SoftApConfiguration` with fixed credentials,
  ADR-002, requires API 26+).
- iOS build not verified on this machine (`xcode-select` points at
  CommandLineTools, not Xcode.app). Android debug APK build verified.

## Next

**Phase 0 - Platform channel PoC.** Implement the native stubs on real devices:
Android custom `SoftApConfiguration` with fixed credentials (host + join), iOS
`NEHotspotConfiguration` join and auto-reconnect. Validate on physical Android
and iOS hardware before any later phase (CLAUDE.md: highest-risk, most
OS-fragile part of the system).
