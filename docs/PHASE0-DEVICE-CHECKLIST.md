# Phase 0 device validation checklist

Code is complete and the APK builds, but Phase 0 is not done until the steps below
pass on real hardware. Emulators/simulators cannot validate hotspot, WiFi join, or
RSSI behavior (CLAUDE.md), so every step here is manual. Record results per device.

## Devices under test

Fill one row per physical device used.

| Device | OEM / model | OS version | API level | Role tested |
|--------|-------------|------------|-----------|-------------|
|        |             |            |           |             |
|        |             |            |           |             |

## Phase 0 - Android host + Android client (2 Android, required)

Run on at least one A/B pair. Steps 5 and 6 are the gate: Phase 0 is not complete
until both pass on at least one pair.

- [ ] 1. Device A: **Create group & host**. Record the returned `HostStartMode`
      (`programmatic` or `manualRequired`), the OS version, and the OEM.
- [ ] 2. If `programmatic`: on device B, confirm the SSID appears exactly as
      `Toice-XXXXXXXX` in the WiFi list.
- [ ] 2m. If `manualRequired`: confirm the app shows the SSID/password + QR and the
      "Open hotspot settings" button deep-links to the tether/wireless settings.
      Create the hotspot by hand with the shown credentials.
- [ ] 3. Device B: **Join** with the SSID/password from A. Confirm the log shows
      `event onClientStateChanged: true`.
- [ ] 4. Device A: **Stop hosting**. Confirm device B logs
      `event onClientStateChanged: false`.
- [ ] 5. Device A: host again with the **same** credentials. Confirm device B rejoins
      without re-entering anything. (Core ADR-002 auto-rejoin guarantee.)
- [ ] 6. Handoff simulation: A stops, B hosts with **identical** credentials, A joins B.
      Confirm the join succeeds. (Makes Phase 2 election meaningful.)
- [ ] 7. If any device is < API 33: confirm `startHost` returns `manualRequired` and the
      Settings deep-link opens.

Notes / anomalies (per-OEM quirks, timings, failures):

```
```

## Phase 0b - iPhone as client (after Phase 0 passes)

No new Swift code. Requires Xcode.app and a free Apple ID.

- [ ] 1. `sudo xcode-select -s /Applications/Xcode.app`, then build + sideload to a
      physical iPhone with a free Apple ID. Confirm signing succeeds now the
      `HotspotConfiguration` entitlement is removed.
- [ ] 2. Open the built-in iPhone Camera and point it at the QR from an Android host.
      Confirm the "Join Network 'Toice-XXXXXXXX'?" banner appears. Tap Join.
- [ ] 3. Confirm the iPhone gets an IP from the Android hotspot
      (Settings > WiFi > network detail).
- [ ] 4. **Decisive test:** turn the Android hotspot off, then on again with the same
      credentials. Confirm the iPhone auto-rejoins with no re-scan. Record the rejoin
      time in seconds.
- [ ] 5. Handoff with 2 Android + 1 iPhone: A stops, B hosts identical credentials,
      confirm the iPhone rejoins on its own. Record the gap.

If step 4 fails (iOS re-prompts every cycle), ADR-002 and ADR-003 must be reopened
before Phase 1. That is the primary risk this phase exists to answer.

mDNS/Bonjour discovery of the host IP is Phase 1, not Phase 0b.
