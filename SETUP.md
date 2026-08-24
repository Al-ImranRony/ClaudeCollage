# Caroullage — One-time Setup (Step 00)

This file documents what was scaffolded in Step 00 and how to get the project
running on a fresh Mac.

> **Current mode:** developing locally with a **personal team** in Xcode.
> Firebase, TelemetryDeck, StoreKit, Fastlane/Match, and Apple Developer Program
> signing are intentionally deferred — they come back in later steps.

---

## What's already scaffolded

| Area | Files |
|---|---|
| Project generator | `project.yml` (XcodeGen) |
| Configs | `Config/Debug.xcconfig`, `Staging.xcconfig`, `Release.xcconfig` |
| App entry (UIKit, programmatic) | `Caroullage/App/AppDelegate.swift`, `SceneDelegate.swift`, `Info.plist` |
| Root navigation | `Caroullage/Coordinators/AppCoordinator.swift` |
| SwiftData stubs | `Caroullage/Core/Models/*.swift` (`CollageProject`, `CollageCell`, enums, `ExportSettings`, `TextOverlay`, `ModelContainerFactory`) |
| Template JSON | `Caroullage/Resources/Templates/{template_schema.json, grid_2up_horizontal.json, grid_4cell_square.json}`, `Resources/CarouselTemplates/carousel_schema.json` |
| Lint / format | `.swiftlint.yml`, `.swiftformat` |
| CI | `.github/workflows/pr.yml` (build + test on PR) |
| Widget extension stub | `CaroullageWidgets/*` |
| Tests | `CaroullageTests/Unit/*`, `CaroullageUITests/UI/*` |
| Gitignore + README | `.gitignore`, `README.md` |

---

## One-time machine setup (every developer)

```bash
# 1. Tooling
brew install xcodegen swiftlint swiftformat

# 2. Generate the Xcode project
cd "/Users/irony/Claude/Projects/Caroullage"
xcodegen generate

# 3. Open Xcode and run
open Caroullage.xcodeproj
# Signing is baked into project.yml (DEVELOPMENT_TEAM), so the team is already
# set on both targets after `xcodegen generate` — no need to re-select it each time.
# To use a different team, change DEVELOPMENT_TEAM in project.yml and regenerate.
# Then Cmd+R on the iPhone 16 simulator.
```

---

## Deferred to later steps

These are intentionally not set up yet. They'll be added when the plan calls for them:

- **Firebase Crashlytics** — added when telemetry is needed (closer to Step 05/06).
- **TelemetryDeck analytics** — same window as Firebase.
- **StoreKit local config + paywall** — re-added in **Step 06 — Deployment**.
- **Fastlane + Match codesigning** — re-added in **Step 06**, alongside paid Apple Developer Program signing.
- **App Store Connect bundle registration** — Step 06.
- **GitHub Actions TestFlight deployment workflow** — Step 06.

For now the project runs on a personal team in Xcode, which is enough through Steps 01–05
(simulator builds + local device sideloads, 7-day cert expiry).

---

## Verifying Step 00 Done Criteria

| Done criterion | How to verify |
|---|---|
| `xcodegen generate` produces a working project | Command exits cleanly; `Caroullage.xcodeproj` opens in Xcode |
| App launches | Cmd+R on iPhone 16 simulator → placeholder screen appears, no crash |
| Tests pass | Cmd+U → smoke unit tests + template parsing tests all green |
| Code coverage enabled | Edit Scheme → Test → Code Coverage is checked (already wired in `project.yml`) |
| CI runs on every PR | Open a no-op PR to `develop` → `.github/workflows/pr.yml` runs green |

---

## Notes / known gaps to revisit later

- **Xcode 26 + iOS 26 SDK** is required by Apple from April 2026 for App Store submissions.
  The `project.yml` declares `xcodeVersion: "26.0"`. CI uses `macos-15` runners;
  switch to `macos-26` once GitHub Actions exposes it.
- App icon is not bundled. Step 06 (Deployment) ships the final 1024×1024 icon.
- Personal team has hard limits: 7-day cert expiry on sideloaded devices,
  no App Groups / Push / extensions with entitlements. The widget extension target
  exists but is empty; if Xcode complains about signing it under a personal team,
  temporarily uncheck "Embed" for the widget in the target settings until Step 05.

---

Next step: open `Steps/Step_01_GridCollage.md`.
