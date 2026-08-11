# Changelog

All notable changes to Toice. See `docs/adr/architecture-decisions.md` for the
architecture this implements and `CLAUDE.md` for the delivery phase plan.

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

## Next

**Phase 0b - iPhone as client.** No new Swift. Sideload to a physical iPhone with a free
Apple ID (confirm signing works now the entitlement is gone), scan the Android host's
`WIFI:` QR with the system Camera, and confirm the iPhone gets an IP. The decisive test:
cycle the Android hotspot with the same credentials and confirm the iPhone auto-rejoins
without re-scanning (validates ADR-002/003 on iOS). If it re-prompts every time, reopen
ADR-002/003 before Phase 1.

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
