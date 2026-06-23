# ClaudeCollage — Execution Steps Index

Execute one step at a time in order. Do not start the next step until all checklist items and tests in the current step are marked done.

The plan is split into **two parts**:

> **Part 1 — Development** *(primary, the bulk of the work)*: Steps 00 → 05. Build the working iOS app from empty Xcode project to feature-complete, polished, simulator-ready application.
>
> **Part 2 — Deployment** *(secondary but essential)*: Step 06. Turn the finished app into a live App Store product — monetization, paywall, onboarding, localization, accessibility, App Store assets, Featuring nomination, submission, post-launch monitoring.

Do not start Part 2 until Part 1 is 100% complete.

---

## Part 1 — Development (Weeks 1–35)

| Step | File | Description | Est. Weeks | Status |
|------|------|-------------|-----------|--------|
| **00** | `Step_00_ProjectSetup.md` | Xcode project, Git, CI/CD, tooling | 1–2 | 🟨 Scaffold complete — pending manual external steps (see SETUP.md) |
| **01** | `Step_01_GridCollage.md` | Rectangular grid collage editor | 3–7 | ⬜ Not started |
| **02** | `Step_02_PolygonCollage.md` | Polygon & custom shape collage | 8–12 | ⬜ Not started |
| **03a** | `Step_03a_StandardTemplates.md` | Frame/story template editor | 13–17 | ⬜ Not started |
| **03b** | `Step_03b_CarouselTemplates.md` | SCRL-style carousel mode | 18–22 | ⬜ Not started |
| **04** | `Step_04_VideoCollage.md` | Video collage + universal export | 23–30 | ⬜ Not started |
| **05** | `Step_05_AIFeaturesAndPolish.md` | AI features, App Intents, widgets, polish | 31–35 | ⬜ Not started |

**End of Part 1:** App is feature-complete and polished — runs end-to-end in the simulator at the quality bar of SCRL. No monetization yet, no localization, no App Store assets. Those live in Part 2.

---

## Part 2 — Deployment (Weeks 36–42 + post-launch)

| Step | File | Description | Est. Weeks | Status |
|------|------|-------------|-----------|--------|
| **06** | `Step_06_Deployment.md` | Monetization, paywall, onboarding, localization, accessibility, compliance, App Store assets, Featuring, submission, post-launch | 36–42 | ⬜ Not started |

**End of Part 2:** App is live on the App Store in 11 languages, monitored for 30 days, ready for v1.1 planning.

---

## How to Use These Files

1. Open the current step file.
2. Read the **Goal** and **Technical Specs** sections before writing any code.
3. Work through the **Checklist** top to bottom.
4. Run the **Tests** section before marking the step done.
5. Verify all **Done Criteria** are met.
6. Update this index (change ⬜ to ✅) and open the next step.

## Reference Documents
- Full plan: `../ClaudeCollage_ProjectPlan.md`
- Bundle ID: `net.pixeltouch.claudecollage`
- Min iOS: 16.0 | Swift 6 | **UIKit (primary)** + **SwiftUI (secondary)** | Metal | AVFoundation | VisionKit
- Required SDK: Xcode 26 + iOS 26 SDK (App Store requirement since April 2026)

## UI Framework Quick Reference

| Surface | Framework |
|---------|-----------|
| App entry (SceneDelegate, UIWindow, UINavigationController) | UIKit |
| Coordinators (navigation) | UIKit (MVVM-C) |
| Grid / Polygon / Template / Carousel / Video editors | **UIKit** |
| Canvas (CAMetalLayer, AVPlayerLayer) | **UIKit** |
| Photo picker (PHPickerViewController) | UIKit |
| Template gallery, sticker grid, frame navigator | UIKit (UICollectionView) |
| Magic eraser brush | UIKit |
| Home screen shell | SwiftUI wrapping UIKit collection |
| Mode selector, Settings, Onboarding, Paywall | SwiftUI |
| Universal Export Sheet | SwiftUI (presented via UIHostingController) |
| Filter strips, simple panels inside editors | SwiftUI (embedded via UIHostingController) |
| Widgets (WidgetKit) | SwiftUI (required) |
| App Intents snippet views | SwiftUI (required) |
