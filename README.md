# ClaudeCollage

iOS Collage Photo & Video Editor — UIKit-primary, SwiftUI-secondary, Metal + AVFoundation.

**Bundle ID:** `net.pixeltouch.claudecollage`
**Min iOS:** 16.0
**Swift:** 6 (strict concurrency)
**Required Xcode:** 26+ (iOS 26 SDK)

## Quick Start

```bash
# 1. Generate the Xcode project from project.yml
brew install xcodegen
xcodegen generate

# 2. Set up code signing (once per machine)
gem install fastlane
fastlane match development

# 3. Open and run
open ClaudeCollage.xcodeproj
# Then Cmd+R
```

## Project Status

See `Steps/STEPS_INDEX.md`. Currently completing **Step 00 — Project Setup**.

## What's where

- `ClaudeCollage/` — main app target source
- `ClaudeCollageWidgets/` — WidgetKit extension
- `ClaudeCollageTests/` — unit + integration tests
- `ClaudeCollageUITests/` — XCUITest UI flows
- `Config/` — `.xcconfig` per environment
- `StoreKit/` — local StoreKit configuration
- `Fastlane/` — Match + lanes
- `Steps/` — execution plan, step-by-step
- `project.yml` — XcodeGen manifest (source of truth for project structure)

## Setup notes for a fresh machine

See `SETUP.md`.
