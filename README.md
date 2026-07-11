# ClaudeCollage

iOS Collage Photo & Video Editor — UIKit-primary, SwiftUI-secondary, Metal + AVFoundation.

**Bundle ID:** `com.devron.claudecollage`
**Min iOS:** 17.0 *(bumped from 16.0 during dev — SwiftData requires 17+. Revisit before Step 06 launch if 16 support is desired.)*
**Swift:** 6 (strict concurrency)
**Required Xcode:** 26+ (iOS 26 SDK)

## Quick Start

```bash
# 1. Generate the Xcode project from project.yml
brew install xcodegen
xcodegen generate

# 2. Open and run
open ClaudeCollage.xcodeproj
# Then Cmd+R
```

Code signing for now uses a **personal team** (set inside Xcode → Signing & Capabilities).
Fastlane / Match, Firebase, TelemetryDeck, StoreKit, and Apple Developer Program signing
will be re-added later — see the Step plan in `Steps/`.

## Project Status

See `Steps/STEPS_INDEX.md`. Currently completing **Step 00 — Project Setup**.

## What's where

- `ClaudeCollage/` — main app target source
- `ClaudeCollageWidgets/` — WidgetKit extension stub (populated in Step 05)
- `ClaudeCollageTests/` — unit + integration tests
- `ClaudeCollageUITests/` — XCUITest UI flows
- `Config/` — `.xcconfig` per environment
- `Steps/` — execution plan, step-by-step
- `project.yml` — XcodeGen manifest (source of truth for project structure)

## Setup notes for a fresh machine

See `SETUP.md`.
