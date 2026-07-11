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
| **00** | `Step_00_ProjectSetup.md` | Xcode project, Git, CI/CD, tooling | 1–2 | ✅ Verified — builds + tests green on Xcode 26.5 / iPhone 16 sim |
| **01** | `Step_01_GridCollage.md` | Rectangular grid collage editor | 3–7 | ✅ Core complete — 8/8 unit tests + UI flow green; editor runs in sim (see Step 01 notes below) |
| **02** | `Step_02_PolygonCollage.md` | Polygon & custom shape collage | 8–12 | ⬜ Not started |
| **03a** | `Step_03a_StandardTemplates.md` | Frame/story template editor | 13–17 | ⬜ Not started |
| **03b** | `Step_03b_CarouselTemplates.md` | SCRL-style carousel mode | 18–22 | ⬜ Not started |
| **04** | `Step_04_VideoCollage.md` | Video collage + universal export | 23–30 | ⬜ Not started |
| **05** | `Step_05_AIFeaturesAndPolish.md` | AI features, App Intents, widgets, polish | 31–35 | ⬜ Not started |

**End of Part 1:** App is feature-complete and polished — runs end-to-end in the simulator at the quality bar of SCRL. No monetization yet, no localization, no App Store assets. Those live in Part 2.

### Step 01 — decisions & deviations (2026-07-11)
- **Renderer:** Core Graphics compositor (`CollageRenderer`) instead of Metal for now. `CanvasView` displays the composited `CGImage` and is structured so a Metal/CAMetalLayer backend can drop in during Step 02's polygon stencil work. All done-criteria met (60fps target not measured headless).
- **Deployment target:** iOS 17.0 (inherited from the Step 00 scaffold's pure-SwiftData choice, not 16.0). Revisit if a Core Data fallback is added.
- **Editor state:** grid editing works on a value snapshot (`GridEditorState`, `Codable`); the `UndoStack` records these (20-step). Persistence stores the JSON blob in `CollageProject.gridStateData` + photos as JPEGs under `Documents/Projects/<id>/images/`.
- **VM binding:** `GridEditorViewModel` uses an `onChange` callback (idiomatic UIKit) rather than `@Observable`.
- **Home:** plain UIKit `HomeViewController` gallery; the SwiftUI shell wrapper is deferred to Step 05 polish.
- **Deferred to later:** live-preview at true 60fps via Metal (Step 02), per-cell drag-preview polish for swap (functional long-press→tap-to-swap works now).
- **Gotcha fixed:** `ModelContext` does not retain its `ModelContainer` — `ProjectStore` must hold the container strongly or the SQLite store disconnects and the next fetch traps.

### Step 01 — performance architecture (must carry into every editor)
The first cut recomposited the whole canvas on the CPU per gesture frame and held full-resolution photos in RAM — laggy and memory-heavy. The corrected model, which Steps 02–05 must follow:
- **GPU canvas, not per-frame CPU compositing.** The live canvas is a layer tree (`CanvasView` → one clipped `CellContentView` per cell). Pan/zoom/rotate mutate the cell's `CGAffineTransform` (Core Animation / GPU). The view model records state but does NOT trigger a re-render during a gesture. Full Core Graphics compositing (`CollageRenderer`) runs ONLY for export + thumbnails.
- **Downsample on import.** `ImageDownsampler` (ImageIO) caps decoded photos at ~1280 px, so RAM stays flat regardless of source resolution. Never decode a full-res photo into memory for display.
- **Filters off the hot path.** `ImageFilterProcessor` (one shared `CIContext`) applies filters asynchronously + coalesced, only when a cell's filters change — never per geometry frame.
- **Export composites off the main thread**; **auto-save is debounced (~0.4 s)** so the thumbnail render + disk write never hitch interaction.
- Verified: 17 unit tests (incl. downsample-cap + full-res-export) + 2 UI flow tests green; real photo import + pan confirmed on the GPU canvas; baseline RSS ~135 MB.

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
- Bundle ID: `com.devron.claudecollage`
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
