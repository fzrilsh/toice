# Changelog

All notable changes to Toice. See `docs/adr/architecture-decisions.md` for the
architecture this implements and `CLAUDE.md` for the delivery phase plan.

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

**Phase 2 - Election scoring + handoff FSM (ADR-003).** Pure Dart, no hardware.
Broadcast payload model (RSSI vector + battery/thermal snapshot + codec),
deterministic ranking engine over `lib/election/fitness_score.dart` (worst-case
RSSI), hysteresis gate (margin + sustained duration, injected clock), handoff
state machine (`stable -> intentBroadcast -> awaitingAcks -> switching ->
stable`, ack timeout to unilateral takeover, single-host invariant), and an
election-daemon interface over a mock data channel + tick clock. Device
validation of Phase 0/0b and Phase 1 audio is deferred to Phases 5/6 until
Android hardware is available.

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
