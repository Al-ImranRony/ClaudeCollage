# Step 00 — Project Setup
**Part:** 1 — Development (Foundation)
**Weeks:** 1–2
**Depends on:** Nothing (this is the first step)
**Unlocks:** Step 01

---

## Goal

Stand up the entire project infrastructure so that any developer on any machine can clone the repo, run one setup command, and be ready to write code. No functionality is built in this step — only the foundation.

This step is part of **Part 1 — Development**. Steps 00 through 05 are Development. Step 06 is Deployment.

---

## Checklist

### Xcode Project
- [ ] Use **Xcode 26+** with the **iOS 26 SDK** (required by Apple for all App Store submissions since April 2026)
- [ ] Create new Xcode project: **App** template, **Storyboard interface** (we will replace the default storyboard with a programmatic `SceneDelegate` setup — see below), Swift language
- [ ] **UI framework strategy:** UIKit is primary (editors, canvas, gestures, AVFoundation surfaces). SwiftUI is secondary (Settings, Paywall, Onboarding, Toasts, Widgets). Top-level app uses `SceneDelegate` + `UIWindow` + `UINavigationController`. SwiftUI screens are presented via `UIHostingController`.
- [ ] Set deployment target to **iOS 16.0**
- [ ] Set Swift language version to **Swift 6** (Build Settings → Swift Language Version)
- [ ] Enable strict concurrency checking (Build Settings → Swift → Strict Concurrency Checking → Complete)
- [ ] Set bundle identifier: `com.devron.caroullage`
- [ ] Set app name: `Caroullage` (display name can be finalized later)
- [ ] Add app icon placeholder (1024×1024 solid color — real icon ships in Step 06 / Deployment)
- [ ] Create three build configurations: **Debug**, **Staging**, **Release**
- [ ] Create three schemes: **Caroullage (Dev)**, **Caroullage (Staging)**, **Caroullage**
- [ ] Create `.xcconfig` files for each configuration:
  - `Config/Debug.xcconfig`
  - `Config/Staging.xcconfig`
  - `Config/Release.xcconfig`
- [ ] Add `API_BASE_URL` and `ENVIRONMENT` as build settings in each `.xcconfig`

### Project Folder Structure
Create these empty groups/folders inside the Xcode project now so they're ready:
```
Caroullage/
├── App/
│   ├── AppDelegate.swift           # UIKit lifecycle
│   ├── SceneDelegate.swift         # UIWindow root setup
│   └── Info.plist
├── Coordinators/                   # MVVM-C navigation
│   └── AppCoordinator.swift
├── Core/
│   ├── Models/
│   ├── Services/
│   ├── Rendering/
│   ├── Intents/                    # App Intents (added in Step 05)
│   ├── Widgets/                    # WidgetKit code (added in Step 05)
│   └── Extensions/
├── Features/
│   ├── Home/                       # SwiftUI shell + UIKit thumbnail collection
│   ├── ModeSelector/               # SwiftUI
│   ├── GridEditor/                 # UIKit (ViewController + ViewModel)
│   ├── TemplateGallery/            # UIKit (UICollectionView)
│   ├── TemplateEditor/             # UIKit
│   ├── CarouselEditor/             # UIKit
│   ├── VideoEditor/                # UIKit (AVPlayerLayer)
│   ├── AI/                         # Step 05 — UIKit hosts, SwiftUI modals
│   ├── Export/                     # SwiftUI (UniversalExportSheet)
│   └── Settings/                   # SwiftUI
└── Resources/
    ├── Templates/
    ├── CarouselTemplates/
    ├── Fonts/
    └── Stickers/
```

### Programmatic App Entry Point (no Storyboard)
- [ ] Delete the default `Main.storyboard`; remove the `UIMainStoryboardFile` key from Info.plist
- [ ] Delete the default `ContentView.swift` (SwiftUI default)
- [ ] Create `App/AppDelegate.swift` (UIKit `UIApplicationDelegate`)
- [ ] Create `App/SceneDelegate.swift` — initializes `UIWindow`, instantiates `AppCoordinator`, calls `coordinator.start()`
- [ ] Create `Coordinators/AppCoordinator.swift` — owns the root `UINavigationController` and routes to the home screen
- [ ] Add to Info.plist:
  ```xml
  <key>UIApplicationSceneManifest</key>
  <dict>
    <key>UIApplicationSupportsMultipleScenes</key><false/>
    <key>UISceneConfigurations</key>
    <dict>
      <key>UIWindowSceneSessionRoleApplication</key>
      <array>
        <dict>
          <key>UISceneConfigurationName</key><string>Default Configuration</string>
          <key>UISceneDelegateClassName</key><string>$(PRODUCT_MODULE_NAME).SceneDelegate</string>
        </dict>
      </array>
    </dict>
  </dict>
  ```
- [ ] Confirm `Cmd+R` launches into an empty UIKit root view controller (we will swap it out for the home screen in Step 01)

### Extension Targets (create stubs now; populate in Step 05)
- [ ] Add **Widget Extension** target named `CaroullageWidgets` — leave empty for now
- [ ] Add **App Intents Extension** capability to main target — App Intents live in the main app bundle, no separate target required
- [ ] Both extensions share an **App Group** (`group.com.devron.caroullage`) — set up the entitlement now

### SwiftData Schema (Stub — no logic yet)
Create stub model files now so the schema is defined before Step 01 coding:
- [ ] `Core/Models/CollageProject.swift` — `@Model class CollageProject` with all fields from the plan
- [ ] `Core/Models/CollageCell.swift` — `@Model class CollageCell`
- [ ] `Core/Models/CollageEnums.swift` — `CollageMode`, `CarouselType`, `CellShape` enums
- [ ] `Core/Models/ExportSettings.swift` — `struct ExportSettings`
- [ ] `Core/Models/TextOverlay.swift` — `struct TextOverlay`
- [ ] Confirm `ModelContainer` is configured in `CaroullageApp.swift`

### Template JSON Schema
- [ ] Write `Resources/Templates/template_schema.json` — the spec document (not a real template, just the schema reference)
- [ ] Write `Resources/CarouselTemplates/carousel_schema.json` — carousel schema reference
- [ ] Create 2 sample rectangular grid templates as JSON:
  - `Resources/Templates/grid_2up_horizontal.json`
  - `Resources/Templates/grid_4cell_square.json`
- [ ] Confirm both parse correctly via a throwaway test in Playgrounds

### Git Repository
- [ ] Initialize Git repository in project root
- [ ] Create `.gitignore` (use standard Swift/Xcode template from gitignore.io)
- [ ] Create `develop` branch from `main`
- [ ] Set branch protection rules on `main`:
  - Require pull request before merging
  - Require at least 1 approval
  - Require status checks to pass (CI)
  - No direct pushes
- [ ] Push initial commit: "chore: initial Xcode project scaffold"

### Code Quality Tools
- [ ] Add `.swiftlint.yml` to project root with these rules enabled:
  ```yaml
  disabled_rules:
    - trailing_whitespace
  opt_in_rules:
    - force_unwrapping
    - explicit_init
    - closure_spacing
  line_length: 120
  ```
- [ ] Add `.swiftformat` with standard Swift formatting rules
- [ ] Add SwiftLint as a build phase Run Script:
  ```bash
  if which swiftlint > /dev/null; then
    swiftlint
  else
    echo "warning: SwiftLint not installed"
  fi
  ```
- [ ] Confirm build succeeds with 0 SwiftLint errors on the empty project

### Dependency Management (Swift Package Manager only)
Add these packages via File → Add Package Dependencies:
- [ ] **Firebase** (`firebase-ios-sdk`) — add `FirebaseCrashlytics` product only — pin to version with privacy manifest + signature
- [ ] **TelemetryDeck** (`telemetrydeck-swift`) — analytics
- [ ] Confirm both packages resolve and build succeeds
- [ ] Verify each SDK ships its `PrivacyInfo.xcprivacy` (required by Apple for SDKs on the [third-party SDK list](https://developer.apple.com/support/third-party-SDK-requirements/))

Do NOT add any other packages yet. Add only when needed in future steps.

### Code Signing (Fastlane Match)
- [ ] Install Fastlane: `gem install fastlane`
- [ ] Run `fastlane init` in project root → choose "Manual setup"
- [ ] Create `Fastlane/Matchfile`:
  ```ruby
  git_url("git@github.com:Al-ImranRony/ios-certs-private.git")
  app_identifier("com.devron.caroullage")
  username("dev3@devron.com")
  storage_mode("git")
  type("development")
  ```
- [ ] Create the private certs repo on GitHub (named `ios-certs-private`, private visibility)
- [ ] Run `fastlane match development` to generate and store development certificate
- [ ] Run `fastlane match appstore` to generate and store distribution certificate
- [ ] Confirm Xcode picks up provisioning profile automatically

### CI/CD Pipeline
Choose **Xcode Cloud** (simpler, built into Xcode) or **GitHub Actions** (more control).

**If Xcode Cloud:**
- [ ] Enable Xcode Cloud in Xcode → Product → Xcode Cloud → Get Started
- [ ] Create workflow: "Pull Request" — triggers on PR to `develop`
  - Build action: Debug
  - Test action: run `CaroullageTests`
- [ ] Create workflow: "Merge to Develop" — triggers on push to `develop`
  - Build action: Staging
  - TestFlight action: distribute to internal group

**If GitHub Actions:**
- [ ] Create `.github/workflows/pr.yml`:
  ```yaml
  name: PR Check
  on:
    pull_request:
      branches: [develop]
  jobs:
    build-and-test:
      runs-on: macos-15
      steps:
        - uses: actions/checkout@v4
        - name: Build & Test
          run: xcodebuild test -scheme "Caroullage (Dev)"
            -destination "platform=iOS Simulator,name=iPhone 16"
  ```

### Crash Reporting & Analytics
- [ ] Add `FirebaseCrashlytics.start()` in `CaroullageApp.init()`
- [ ] Add `TelemetryDeck.initialize(configuration:)` in `CaroullageApp.init()`
- [ ] Add `GoogleService-Info.plist` to project (download from Firebase Console)
- [ ] Confirm both initialize without errors on simulator launch

### StoreKit Configuration (Local Testing)
- [ ] Create `StoreKit/Caroullage.storekit` configuration file
- [ ] Add 4 products:
  ```
  com.devron.caroullage.premium.weekly    (Auto-Renewable Subscription, $2.99/week)
  com.devron.caroullage.premium.monthly   (Auto-Renewable Subscription, $4.99/month)
  com.devron.caroullage.premium.yearly    (Auto-Renewable Subscription, $24.99/year)
  com.devron.caroullage.premium.lifetime  (Non-Consumable, $49.99)
  ```
- [ ] Set Debug scheme to use this StoreKit configuration file

### Testing Setup
- [ ] Confirm `CaroullageTests` target exists (Xcode creates it automatically)
- [ ] Confirm `CaroullageUITests` target exists
- [ ] Create folder structure inside test targets:
  ```
  CaroullageTests/
  ├── Unit/
  └── Integration/
  CaroullageUITests/
  └── UI/
  ```
- [ ] Run `Cmd+U` → all tests pass (there are none yet — just confirm 0 failures)
- [ ] Enable code coverage: Edit Scheme → Test → Code Coverage → check "Gather coverage"

---

## Tests for This Step

No unit tests are written in Step 00. The verification is:

- [ ] `Cmd+B` builds successfully with 0 errors, 0 SwiftLint errors
- [ ] `Cmd+U` runs with 0 failures
- [ ] `firebase crashlytics:debug` or simulator launch shows Firebase initialized in console
- [ ] Xcode Cloud / GitHub Actions CI runs and shows green on a test PR

---

## Done Criteria

All of the following must be true before moving to Step 01:

- [ ] Any developer can clone the repo, run `fastlane match development`, open the project, and hit `Cmd+R` to run on simulator — with zero manual certificate steps
- [ ] CI runs automatically on every PR and shows pass/fail in GitHub
- [ ] SwiftData `ModelContainer` is configured and the app launches without crashing
- [ ] The 2 sample grid template JSON files parse without errors
- [ ] Code coverage is enabled in the test scheme

---

## Notes for Next Step

When you start Step 01, the first thing you'll build is the `CollageLayoutEngine`. Write its unit tests in `CaroullageTests/Unit/CollageLayoutEngineTests.swift` as you go.
