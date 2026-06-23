# ClaudeCollage — One-time Setup (Step 00)

This file documents what was scaffolded in Step 00, what each developer must do
once on their machine, and the manual external steps that need your Apple/GitHub
credentials.

> **TL;DR for the project lead:** items in `(BLOCKED — you)` below cannot be done
> from inside the scaffolder. Run them in order before merging Step 00.

---

## What's already scaffolded

| Area | Files |
|---|---|
| Project generator | `project.yml` (XcodeGen) |
| Configs | `Config/Debug.xcconfig`, `Staging.xcconfig`, `Release.xcconfig` |
| App entry (UIKit, programmatic) | `ClaudeCollage/App/AppDelegate.swift`, `SceneDelegate.swift`, `Info.plist` |
| Root navigation | `ClaudeCollage/Coordinators/AppCoordinator.swift` |
| SwiftData stubs | `ClaudeCollage/Core/Models/*.swift` (`CollageProject`, `CollageCell`, enums, `ExportSettings`, `TextOverlay`, `ModelContainerFactory`) |
| Template JSON | `ClaudeCollage/Resources/Templates/{template_schema.json, grid_2up_horizontal.json, grid_4cell_square.json}`, `Resources/CarouselTemplates/carousel_schema.json` |
| Lint / format | `.swiftlint.yml`, `.swiftformat` |
| Fastlane | `Fastlane/{Fastfile, Matchfile, Appfile}`, `Gemfile` |
| StoreKit local | `StoreKit/ClaudeCollage.storekit` (4 products) |
| CI | `.github/workflows/{pr.yml, develop.yml}` |
| Widget extension stub | `ClaudeCollageWidgets/*` |
| Tests | `ClaudeCollageTests/Unit/*`, `ClaudeCollageUITests/UI/*` |
| Gitignore + README | `.gitignore`, `README.md` |

---

## One-time machine setup (every developer)

```bash
# 1. Tooling (Homebrew)
brew install xcodegen swiftlint swiftformat
brew install --cask fastlane

# 2. Ruby gems for Fastlane
gem install bundler
bundle install

# 3. Generate the Xcode project
cd /path/to/ClaudeCollage
xcodegen generate

# 4. Pull signing certs (after the cert repo + Match are set up — see below)
bundle exec fastlane certs_dev

# 5. Open Xcode and run
open ClaudeCollage.xcodeproj
# Cmd+R should launch the placeholder screen on the iPhone 16 simulator.
```

---

## External / manual steps (BLOCKED — you)

These need your Apple ID, GitHub credentials, and team membership. Do them in order.

1. **(BLOCKED — you) Register the bundle ID**
   - App Store Connect → Identifiers → register `net.pixeltouch.claudecollage`
   - Also register `net.pixeltouch.claudecollage.widgets` (widget extension)
   - Enable App Groups capability: `group.net.pixeltouch.claudecollage`

2. **(BLOCKED — you) Create the GitHub repos**
   - Public/internal source repo: `pixeltouch/claude-collage-ios`
     - Push the contents of this folder to `main`
     - Create `develop` from `main`
     - Branch protection on `main`: require PR, ≥1 approval, status checks pass, no direct push
   - Private cert repo: `pixeltouch/ios-certs-private` (empty, private)
     - Used by Fastlane Match to store encrypted signing material

3. **(BLOCKED — you) Initialize Fastlane Match**
   ```bash
   bundle exec fastlane match development   # generates dev cert + profile, pushes to ios-certs-private
   bundle exec fastlane match appstore      # generates distribution cert + profile
   ```
   Save the chosen Match password — store it as the `MATCH_PASSWORD` secret in GitHub.

4. **(BLOCKED — you) Firebase Crashlytics**
   - Create a Firebase project, add an iOS app for `net.pixeltouch.claudecollage`
   - Download `GoogleService-Info.plist`
   - Drop it at `ClaudeCollage/GoogleService-Info.plist` (the file is in `.gitignore`; distribute via a secrets manager or 1Password)
   - Re-run `xcodegen generate`

5. **(BLOCKED — you) TelemetryDeck**
   - Create an app at https://dashboard.telemetrydeck.com
   - Copy the app UUID into `ClaudeCollage/App/Info.plist` under the existing `TelemetryDeckAppID` key

6. **(BLOCKED — you) Apple Developer team ID**
   - Fill `team_id` in `Fastlane/Appfile`
   - Fill `DEVELOPMENT_TEAM` per-config or rely on Xcode auto-pick after `match`

7. **(BLOCKED — you) GitHub Actions secrets**
   Add these repo secrets so `.github/workflows/develop.yml` succeeds:
   - `MATCH_PASSWORD`
   - `MATCH_GIT_BASIC_AUTHORIZATION` (base64 of `username:personal-access-token` for the cert repo)
   - `APP_STORE_CONNECT_API_KEY_ID`, `APP_STORE_CONNECT_API_ISSUER_ID`, `APP_STORE_CONNECT_API_KEY_CONTENT` (App Store Connect API key — preferred over `FASTLANE_USER`/`PASSWORD`)
   - `FASTLANE_USER` / `FASTLANE_PASSWORD` (optional fallback)

8. **(BLOCKED — you) Featuring nomination**
   - App Store Connect → Apps → ClaudeCollage → Features → submit nomination
   - Per the plan, do this 12 weeks before launch — start now even though the app isn't built

---

## Verifying Step 00 Done Criteria

After completing the manual steps above:

| Done criterion | How to verify |
|---|---|
| Clone + `fastlane match development` + `Cmd+R` works | Fresh checkout on a second machine; should run with zero manual cert steps |
| CI runs on every PR | Open a no-op PR to `develop` → `.github/workflows/pr.yml` runs green |
| `ModelContainer` configured, app launches | Launch on simulator → placeholder screen appears, no crash |
| Sample JSON parses | `Cmd+U` → `TemplateJSONParsingTests` passes |
| Code coverage enabled | Edit Scheme → Test → Code Coverage is checked (already wired in `project.yml`) |

---

## Notes / known gaps to revisit later

- **Xcode 26 + iOS 26 SDK** is required by Apple from April 2026 for submissions. The `project.yml` declares `xcodeVersion: "26.0"`. CI uses `macos-15` runners; switch to `macos-26` once GitHub Actions exposes it.
- The Storyboard from the default Xcode template is not present — we never added one. The scene manifest in `Info.plist` points straight at `SceneDelegate` (matches Step 00 plan: "delete the default Main.storyboard").
- App icon is not bundled. Step 06 (Deployment) ships the final 1024×1024 icon. For dev builds add a placeholder asset catalog in `ClaudeCollage/Resources/Assets.xcassets` when needed.
- `SwiftLint` is currently expected on the developer's machine. We did not add a Build Phase Run Script in `project.yml` to keep the manifest minimal — add it inside Xcode after first generation, or extend `project.yml` with a `preBuildScripts` entry.

---

Next step: open `Steps/Step_01_GridCollage.md`.
