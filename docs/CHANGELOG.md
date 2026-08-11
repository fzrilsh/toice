# Changelog

All notable changes to Toice. See `docs/adr/architecture-decisions.md` for the
architecture this implements and `CLAUDE.md` for the delivery phase plan.

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
