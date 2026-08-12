# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What This Is

**Toice** (Tour + Voice) — offline, peer-to-peer voice intercom app for motorcycle touring convoys (Android + iOS). No internet or cellular connection required for the core communication feature; all voice traffic runs device-to-device over a locally hosted WiFi hotspot. Target: groups of 5-7 riders, 60-80 km/h, no fixed host device, no backend server for the core feature.

Full architecture decisions and their rationale live in `docs/adr/architecture-decisions.md`. This file assumes those decisions; if a task seems to contradict one of them, stop and flag it rather than improvising around it.

## Build

```bash
# Get dependencies
flutter pub get

# Regenerate platform channel bindings / codegen (if using pigeon or similar for native bridges)
flutter pub run pigeon --input pigeons/*.dart

# Debug build
flutter build apk --debug        # Android
flutter build ios --debug --no-codesign   # iOS

# Release build
flutter build apk --release
flutter build ios --release
```

Native platform code (Swift under `ios/Runner/`, Kotlin under `android/app/src/main/kotlin/`) must be kept in sync with any platform channel method signatures defined in Dart. See `docs/adr/architecture-decisions.md` ADR-006 for what is native vs. Dart.

## Run

```bash
flutter run -d <device_id>
```

Core features (hotspot hosting, WebRTC, foreground service / background audio) require a physical device. Simulators/emulators cannot validate hotspot or BLE/WiFi RSSI behavior; do not treat emulator runs as sufficient validation for anything touching ADR-001 through ADR-005.

## Test

```bash
flutter test                          # unit + widget tests
flutter test test/election/           # single directory, e.g. election scoring logic
flutter drive --target=test_driver/app.dart   # integration tests, physical device required
```

Election scoring (ADR-003), handoff state machine, and audio priority logic (ADR-004) are pure Dart and must have unit test coverage. Anything crossing a platform channel (hotspot, background service, sensors) needs a manual/integration test checklist per platform, not just unit tests, since OS behavior varies by version and OEM.

## Key Architecture Decisions

See `docs/adr/architecture-decisions.md` for full context and rationale on each. Summary:

- **Topology:** single-hotspot star (one device hosts, rest join as clients), not mesh. WiFi Direct/NAN is not usable cross-platform because iOS does not expose it to third-party apps.
- **Bootstrap:** QR code encodes a fixed SSID/password/group ID generated once at group creation. Reused for every subsequent host so iOS auto-rejoins without repeated prompts (`NEHotspotConfiguration`).
- **Host election:** continuous, composite fitness score (worst-case RSSI + battery + thermal), not a fixed backup device. Explicit intent-broadcast-and-ack handoff protocol, hysteresis to prevent flapping. Never two APs active at once.
- **Audio:** WebRTC (`flutter_webrtc`), Opus with DTX enabled, host-side mixing (not full mesh), loudest-speaker-wins ducking on other streams.
- **Background execution:** Android foreground service with persistent notification; iOS background audio mode. This is a hard requirement, not an enhancement — the app must survive screen-off and other apps (GPS nav) in foreground.
- **No backend for the core feature.** Backend (accounts, trip history, offline map distribution) is a separate, deferred concern and must not block core delivery.
- **Group size is capped at 5-7 riders by design.** Do not introduce sub-group sharding to scale beyond this; it was explicitly rejected.

## Project Structure

```
lib/
  election/       # RSSI/battery/thermal scoring, handoff state machine (pure Dart, unit tested)
  audio/           # WebRTC session mgmt, DTX config, ducking/speaker-priority logic
  app/             # Reactive app state store (SessionStore, binds session+audio+host)
  native_bridge/   # Platform channel method definitions and Dart-side wrappers
  group/           # QR bootstrap, group/session credential state
  ui/              # Screens, widgets
ios/Runner/        # Swift: NEHotspotConfiguration, background audio mode, sensor reads
android/app/.../   # Kotlin: SoftApConfiguration, foreground service, sensor reads
docs/adr/           # Architecture decision records
```

If a new top-level `lib/` directory is added, add it to this list and to the dependency notes below.

## Native Platform Notes

- **Android hotspot:** use a custom `SoftApConfiguration` with fixed SSID/password from the group session, not `startLocalOnlyHotspot` (generates random credentials per call, incompatible with the fixed-credential handoff design in ADR-002).
- **iOS join:** system Camera reads a standard `WIFI:S:<ssid>;T:WPA;P:<password>;;` QR, one user approval per device per group session, auto-rejoins afterward as long as SSID/password are unchanged. `NEHotspotConfiguration` was dropped (paid-account entitlement, breaks free-provisioning signing); see ADR-002 addendum. A paid account could re-add it later as an in-app path without changing the credential format.
- **Do not attempt concurrent AP + WiFi Direct/P2P roles on one device.** Explicitly rejected in ADR-001 due to chipset-dependent support.
- **BT/WiFi coexistence** on the 2.4GHz band is chipset-dependent. No software mitigation planned; document as a minimum-spec / compatibility concern, and keep wired headset as a supported fallback path in the audio input selection UI.

## Delivery Phases

Original sequencing validated the riskiest, most OS/OEM-dependent pieces first. As of 2026-08-11 the roadmap is reordered: no physical Android devices are available, so pure-Dart/Flutter work (Phases 2-4) is front-loaded and hardware-gated work (Phases 5-8) is deferred until devices return. This proves logic, not the product. The open product risk (fixed-credential hotspot + handoff on real iOS/Android OEMs) stays unanswered until Phase 5.

Done:

- **Phase 0 (code complete, device validation deferred to Phase 5).** Fixed-credential hotspot bridge: Android host via `SoftApConfiguration` reflection with manual fallback, Android client join, iOS system-Camera `WIFI:` QR join (dropped `NEHotspotConfiguration`, see ADR-002 addendum).
- **Phase 1 mock-track (code complete, device validation deferred to Phase 6).** WebRTC session state machine behind a transport boundary (`lib/audio/`), call screen bound to live connection state, driven by mock session/signaling. Real audio deferred.
- **Phase 2 (code complete, pure Dart).** Election scoring + handoff FSM (ADR-003): broadcast payload model + score mappers, deterministic ranking (worst-case RSSI, iOS excluded), hysteresis gate, handoff state machine, election daemon over a mock channel + tick clock. All under `lib/election/`, unit tested.
- **Phase 3 (code complete, pure Dart).** Audio priority + state management (ADR-004): loudest-speaker-wins ducking engine (hold-time hysteresis), speaker-level source boundary + active-speaker tracker, DTX/headset-conditional-AEC config model (`lib/audio/`), and `SessionStore` reactive state binding (`lib/app/`). Call screen renders the roster with a live speaking indicator. Decision layer only; real audio at Phase 6.

Pure-Dart phases (no hardware, do these next):

4. **Phase 4 - QR bootstrap + full UI (ADR-002).** QR encode/decode round-trip with the deferred nonce field, in-app QR scanner dep for Android (iOS stays system Camera), trip-lifetime credential persistence, real create/join/call/roster screens replacing the Phase 0 PoC.

Hardware-gated phases (deferred until Android devices are back):

5. **Phase 5 - Phase 0/0b device validation.** Run `docs/PHASE0-DEVICE-CHECKLIST.md` on 2 Android (gate: same-credential rejoin + handoff sim), then iPhone client. This is the real product risk gate; everything above assumes it passes.
6. **Phase 6 - Real WebRTC audio + host-side mixing (ADR-004).** Wire `WebRtcPeer.create` + socket signaling, mic capture, host-side mixing, ICE over the hotspot LAN, apply Phase 3 ducking + DTX config to live tracks, measure latency/quality baseline.
7. **Phase 7 - Background execution (ADR-005).** Android foreground service + persistent notification, iOS background audio mode; survive screen-off and GPS-nav foreground.
8. **Phase 8 - Battery/thermal optimization + sensors (ADR-003/005).** Native RSSI/battery/thermal reads feeding the Phase 2 election engine (mock-fed until now), DTX tuning, adaptive broadcast interval, screen-off daemon, BT/WiFi coexistence minimum-spec documentation.

Do not treat Phases 2-4 completion as product validation. The native hotspot/audio behavior remains the highest-risk, most OS-fragile part of the system and is only proven at Phase 5+ on real hardware.

## Branching Strategy

`action/short-description`, e.g. `feat/hotspot-bridge`, `fix/handoff-flapping`, `develop`, `staging`. No direct commits to `main`.

## Git Workflow

Flow: feature branch → PR into `develop` → `staging` → `main`. Push feature branches only, never force-push shared branches.

### Commit Message Format

```
<type>(<scope>): <description>

<body>

<footer>
```

- `<type>`: one of `feat` (new feature), `fix` (bug fix), `docs` (documentation), `chore` (maintenance or tooling), `refactor` (neither fixes a bug nor adds a feature), `test`.
- `<scope>`: the area touched, e.g. `election`, `audio`, `native-ios`, `native-android`, `ui`.
- Blank line before the body. Body is optional but expected for anything non-trivial: explain the full change and why, not a one-liner.
- Footer optional, for breaking changes or issue references.

### Attribution

Never add Claude attribution to commits, PRs, or issues. No `Co-Authored-By: Claude`, no "Generated with Claude Code", no emoji trailer, no `--author` override.

### Writing Style

No em dashes (`—`) anywhere: commit messages, code comments, docs, PR bodies. Use a comma, a colon, parentheses, or split the sentence. Same for other AI-slop tells: en dashes used as punctuation, `–`, curly quotes, decorative emoji, and filler openers like "In today's fast-paced world" or "It's worth noting that". Plain ASCII punctuation, plain sentences.

### When to Commit and Push

- Commit after every completed task. Do not batch several tasks into one commit.
- Push only at the end of a phase, or when the job is otherwise finished. Intermediate task commits stay local.

## Pre-commit / Pre-push Hooks

Managed via `lefthook`. `lefthook.yml` should run:
- pre-commit: `dart format --set-exit-if-changed`, `flutter analyze`
- pre-push: `flutter test`

Set up `lefthook.yml` + `lefthook install` before first commit if not already present.

## Ambiguity

If a requirement, scope, or design choice is ambiguous, or appears to conflict with a decision in `docs/adr/architecture-decisions.md`, use `AskUserQuestion` before implementing. Do not guess, and do not silently reopen a decision already made in the ADR (e.g. re-introducing mesh topology, sub-grouping, or a backend dependency for the core feature).

## Post-Phase Review

After finishing any task or delivery phase, review the result against the relevant ADR section(s) before considering it done. Confirm it's correct and complete on real devices for anything touching native platform code, not just "compiles" or "runs on emulator".

When a phase is complete, update `docs/CHANGELOG.md` with the same structure as below before calling it done:
- Add new phase section with completion date and status
- List all implemented features, files created/changed
- Note any deviation from the ADR and why
- Replace the existing "Next" section with the upcoming phase. Exactly one "Next" section at any time, directly under the newest phase.
- Header format: `## Phase N - Title (date) ✅`, newest first. Non-phase maintenance passes may use `## Title (date)` instead.

## Spec Authority

`docs/adr/architecture-decisions.md` is the source of truth for architecture and behavior. Any deviation or ambiguity → ask via `AskUserQuestion`, don't improvise silently.