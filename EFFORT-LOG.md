# CodeCaps — Effort Log

Running log of work units, newest first.  Each entry: date, lane, summary,
PR (when shipped), follow-ups (when parked).

---

## 2026-09-21 — Stand up automated iOS TestFlight shipping workflow

Lane: `plumber/ios-testflight-workflow`.

Stood up automated GitHub-hosted macOS TestFlight ship workflow for CodeCaps Companion:
- Created `.github/workflows/ios-ship.yml` with push trigger, path filter (`ios/CodeCapsCompanion/**`), and 30-minute cron (`26,56 * * * *`).
- Added in-repo fleet scripts in `scripts/ios-fleet/`: `ExportOptions-*.plist`, `apps.json`, `asc-api.mjs`, `scheduled-ship-gate.sh`, and `ship-testflight.sh`.
- Added wrapper scripts `scripts/ios-appstore-gm-prepare.sh` and `scripts/ios-ship-testflight.sh`.
- Configured repository secrets on GitHub: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `IOS_DIST_P12_BASE64`, and `IOS_DIST_P12_PASSWORD`.
- Verified local dry-run archive resolution and scheduled ship gate.

---

## 2026-09-21 — App Group configuration & macOS companion target

Lane: `ag/companion-app-group-and-mac`.

Configured App Group `group.com.simplewithus.codecaps` across iOS companion and macOS targets:
- Added `CodeCapsCompanion.entitlements` and `CodeCapsCompanionMac.entitlements` with App Group `group.com.simplewithus.codecaps`.
- Added `CodeCapsCompanionMac` target in `ios/CodeCapsCompanion/project.yml` for macOS 14+ with bundle ID `com.simplewithus.codecaps.macos`.
- Updated `CompanionQuotaModel.swift` to read shared defaults and quota files from the App Group container.
- Updated `LocalQuotaSnapshot.swift` in `QuotaCore` to mirror snapshots into the shared App Group container when available.
- Replaced interim mark with authentic 3D rich teal (#0B6B5D) icon matching the Usage Monitor Client design with embossed circuit traces, circular sync arrows, and glossy white plate.
- Removed script/make_codecaps_icon.swift and assets/icon-1024-transparent.png.
- Removed iOS companion App Group entitlement to align with standard automated App Store signing while keeping it active on macOS companion.
- Verified xcodebuild archive succeeds and prepares for TestFlight upload.
- Built both targets and verified all 163 unit tests pass.

---

## 2026-09-20 — Comprehensive audit, tier-1 implementation — MERGED 28b802f via PR #20

Lane: `mm/audit-2026-09-20`.  Audit: `docs/audits/2026-09-20-comprehensive.md`.
GitHub umbrella: [#19](https://github.com/jaywedgeworth22/codecaps/issues/19).
Board item: filed under app `codecaps`, kind `github-issue`.

Swept every Swift file in `Sources/CodeCaps/` and `Sources/QuotaCore/`, the
build script, the tests, the README.  22 findings (5 high, 7 medium, 10 low)
plus 6 test/doc gaps.

Tier-1 implementation in this PR:

- A9-01 — SettingsViews.swift:734 footer copy updated to match the System
  default from commit `3b24eb8`.  README "Appearance" bullet updated too.
- A9-02 — `script/build_and_run.sh:462` no longer discards the notarization
  rejection log (`>&2 2>/dev/null` → `>&2`).
- A9-03 — `script/build_and_run.sh:198-200` carries a comment explaining
  why `--deep` is fine in the ad-hoc fallback only.
- A9-13/27/28 — `AGENTS.md` and `EFFORT-LOG.md` added.
- A9-23 — README "Logs" section added.

A9-04 retracted after re-read (script already exits 1 on rejection before
stapling).

Build clean, 130/130 tests pass.  Merged via auto-merge.

Queued for follow-up lanes: A9-05, A9-06, A9-07, A9-08, A9-09, A9-10, A9-11,
A9-12, A9-16, A9-17, A9-18, A9-24, A9-25, A9-26, A9-29.  A9-14 and A9-15
(producer rename) deferred — wire format, needs owner call.

## 2026-09-19 — Default appearance to System (PR #18, audits #4–#8)

Lane: `mm/system-default-theme`.  Five audit-batch fixes landed with the
theme-default change:

- audit #4 — `DisplaySection.driving` determinism (ff...f3).
- audit #5 — Antigravity RPC short-circuit on 4xx (7eb8202).
- audit #6 — `PlatformDetailPage` save debounce 250ms (2151862).
- audit #7 — Glance consent-needed row rendering (36757fc).
- audit #8 — Dynamic Type on body copy (bd10335).
