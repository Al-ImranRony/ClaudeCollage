# Caroullage — iOS Collage Photo & Video Editor
## Final Project Plan (Pre-Development)
**Version:** 3.0 — Final (Development / Deployment Split)
**Date:** 2026-06-13
**Platform:** iOS (iPhone-first, iPad-compatible)
**Developer:** Devron (devron.com)
**Bundle ID:** `com.devron.caroullage`

---

## How This Plan Is Organized

This plan is split into **two parts** that map directly to the execution steps in `/Steps`:

> **Part 1 — Development** *(primary, the bulk of the work)*
> Steps 00 → 05D. Build the working iOS app: project setup, the three creative pillars (grid/polygon, templates + carousel, video), the universal export system, AI-powered features, and complete UI/UX polish. By the end of Part 1, the app is fully functional and indistinguishable from a chart-topping competitor when running in the iOS Simulator.
>
> **Part 2 — Deployment** *(secondary but essential, executed after Development is complete)*
> Step 06. Take the finished, working app from Part 1 and ship it: StoreKit 2 subscriptions, paywall, onboarding funnel, localization, accessibility, App Store assets, Featuring nomination, App Review submission, and post-launch monitoring. All consolidated into a single deployment step.

The two parts have different mindsets:
- **Development** = build the experience. Code, tests, simulator validation, internal polish.
- **Deployment** = ship the experience. Marketing, money, App Store, compliance, real users.

Do not start Deployment until Development is 100% done and the app runs end-to-end in the simulator at the quality bar of SCRL.

---

## 1. Executive Summary

Caroullage is a native iOS collage editor built around three creative modes: geometric grid/polygon collages, SCRL-style template + carousel collages, and video collage — augmented with on-device AI features (subject lifting, magic eraser, AI auto-layout, generative backgrounds via Image Playground). A unified social-media export system serves every editor and produces platform-correct files for Instagram, TikTok, YouTube, X, WhatsApp, and print.

The product leverages PixelTouch's existing iOS infrastructure (Blur Photo Editor's StoreKit setup, developer account, codebase patterns) and competes directly with SCRL, LiveCollage, Photoroom, Photoleap, and Pic Stitch.

A progressive unit testing strategy introduces tests incrementally alongside each feature — written for a developer learning testing on the job, not all at once.

---

## 2. Competitive Analysis

### 2.1 Reference Apps

| App | Rating | Reviews | Size | Min iOS | Monetization |
|-----|--------|---------|------|---------|--------------|
| **SCRL** (Appostrophe AB) | 4.8 ⭐ | 103K | 140.5 MB | iOS 16.0 | Freemium — $4.99/wk or $34.99/yr |
| **LiveCollage** (Video Editor PTE) | 4.8 ⭐ | 164K | 265.2 MB | — | Freemium — IAP |
| **Photoroom** | 4.8 ⭐ | 1M+ | 180 MB | iOS 16.0 | Freemium — $9.99/mo |
| **Pic Stitch** (Maple Media) | — | — | — | — | Freemium — IAP |
| **Blur Photo Editor** (PixelTouch) | 4.4 ⭐ | 10K | 256.2 MB | iOS 15.0 | Freemium — $2.99–$49.99 |

### 2.2 Competitive Gaps We Win On

1. **Video export quality** — SCRL's video export is noticeably degraded (flagged in reviews). We use a direct `AVAssetReader` → `AVAssetWriter` pipeline with no `AVAssetExportSession` resampling.
2. **Storage bloat** — SCRL uses excessive temp storage during editing. We use a streaming render pipeline.
3. **Paywall aggressiveness** — Blur Photo Editor's $7.99/week pricing drew backlash. We use a generous free tier with annual-default pricing.
4. **Polygon/shape collages** — No major competitor combines freeform shape collages with template collages in one app.
5. **True carousel support** — Most apps offer carousel as an afterthought. We design it as a first-class feature with the same quality bar as SCRL.
6. **On-device AI built-in** — VisionKit subject lifting, Image Playground generative backgrounds, magic eraser — zero infra cost, no subscription gate on basic AI use.
7. **App Intents + Shortcuts + Widgets** — "Create Collage from Last 9 Photos" as a Spotlight/Siri/Action Button action. Competitors don't surface this.
8. **Live Activities during export** — Lock Screen / Dynamic Island export progress (CapCut-style).

---

## 3. Product Definition

### 3.1 Core Feature Pillars

---

#### Pillar 1 — Geometric Grid & Polygon Collage

Create collages using structured geometric layouts.

**Rectangular grids:**
- 2–9 cell layouts: 1+1 horizontal, 1+1 vertical, 2+1, 1+2, 3+3, 2+2, 1+3, T-split, L-split, etc.
- Adjustable border/gap width (0–20pt)
- Adjustable corner radius per cell
- Background: solid color, gradient, or texture

**Polygon shapes:**
- Diagonal splits (left-lean, right-lean)
- Triangular cells
- Hexagonal grids
- Circular/oval cells
- Custom bezier boundary editor (advanced)

**Per-cell controls (both grid and polygon):**
- Pan, pinch-zoom, rotate photo within cell
- Swap cells by drag
- Aspect-ratio lock toggle
- Filter strip: brightness, contrast, saturation, warmth, sharpness

---

#### Pillar 2 — Template, Frame & Carousel Collage

SCRL-quality curated template system with carousel as a first-class mode.

##### 2a. Standard Templates
- Pre-designed templates organized by category: Story, Grid, Minimal, Seasonal, Travel, Mood Board, Birthday, etc.
- Each template contains: photo zones, text zones, sticker/overlay zones, decorative elements, background
- Canvas sizes: 1:1 (Instagram post), 9:16 (Story/Reel), 4:5 (portrait), 16:9 (landscape), A4 (print)
- 50+ curated templates at launch; 10 new templates added monthly post-launch

##### 2b. Carousel Templates (Inspired by SCRL)
Carousel is a distinct creation mode within Pillar 2, not a sub-option.

**What a carousel is:**
A set of 2–10 linked frames (slides) designed to be swiped through on Instagram or TikTok. The frames have a cohesive visual design and can optionally create a seamless panoramic image that spans across all slides.

**Carousel types:**

| Type | Description |
|------|-------------|
| **Panoramic carousel** | A single wide image split across N frames. When swiped, the scene flows continuously — identical to SCRL's signature feature. |
| **Matched carousel** | Each frame is independently composed but shares a consistent template (same layout, font, color palette). |
| **Scroll-through story** | Sequential frames that tell a narrative — each frame has photo + text block. Common for "tips" or "before/after" posts. |
| **Grid preview carousel** | First frame shows the full 3×3 or 4×4 grid; subsequent frames reveal individual cells. |

**Carousel editor workflow:**
1. Choose carousel type from gallery
2. Choose canvas ratio (9:16 for Stories, 1:1 or 4:5 for feed)
3. Set number of frames (2–10)
4. For panoramic: import one wide photo or multiple photos; app stitches and splits automatically
5. For matched/scroll: fill each frame sequentially; copy frame style to adjacent frames
6. Preview carousel with swipe animation inside the app before export
7. Export as: individual images (numbered) or video slideshow with swipe animation

**Carousel-specific features:**
- **Frame navigator:** Horizontal strip at the bottom showing all frames; tap to jump, drag to reorder
- **Sync editing:** Apply the same edit (font change, background color) to all frames at once with one toggle
- **Carousel preview player:** Full-screen swipe simulation before export
- **Slide count indicator:** Shows "1 / 6" overlay (optional, toggleable)
- **Seamless edge matching:** For panoramic carousels, pixel-perfect alignment at frame edges
- **Safe-zone overlay:** Visual guide showing where Instagram/TikTok UI covers the canvas
- **Export bundle:** Exports as numbered ZIP (frame_01.jpg ... frame_06.jpg) or a video montage

##### 2c. Text, Stickers & Overlays (all template modes)
- Font picker with custom font support (TTF/OTF import)
- Text styling: size, color, alignment, letter spacing, line height, opacity
- Sticker library: bundled packs + downloadable premium packs
- Shape overlays: lines, arrows, geometric accents
- Freeform canvas with snap-to-grid guides

---

#### Pillar 3 — Video Collage

Mixed photo and video collage with high-quality export.

- Each cell holds a photo or a video clip
- Video trim per cell (in/out point scrubber)
- Video loop, mute, per-cell volume control
- Synchronized background audio track
- Auto-beat-sync (CapCut-style): align cell transitions to detected music onsets via `AVAudioEngine`
- Animated cell transitions: crossfade, slide, zoom
- Live Photo / motion sticker import preserving motion
- Export: 1080p H.264 (free), HEVC 4K (premium)
- Memory-efficient streaming render — no temp file bloat
- **Live Activity** showing export progress on Lock Screen / Dynamic Island

**Engineering note:** Use direct `AVAssetReader` → `AVAssetWriter` pipeline. Avoid `AVAssetExportSession` and intermediate transcodes. This directly fixes SCRL's known video quality degradation bug.

---

#### Pillar 4 — On-Device AI Features (NEW)

Table-stakes AI for 2026 — all on-device, all free in the basic tier, no infra cost.

- **Subject lifting / background removal** — VisionKit `ImageAnalyzer.subjectLift` (iOS 17+). One-tap remove a subject and use it as a sticker in another cell.
- **Magic eraser / object removal** — Vision framework segmentation + Core Image inpainting.
- **AI auto-layout** — Drop 10 photos, get 5 suggested collages. Uses Vision face/saliency detection to compose cells around important content.
- **Generative backgrounds** — Apple's Image Playground framework (iOS 18.2+). Generate a background based on a text prompt. Gracefully degrades on non-Apple-Intelligence devices.
- **Smart suggestions** — Analyze photo set; suggest a matching template by dominant color, time, location metadata.
- **Photo→sticker** — Long-press a photo subject → lifted PNG sticker added to current canvas.

---

### 3.2 Supporting Features (All Pillars)

- Photo picker via SwiftUI `PhotosPicker` (no library permission needed)
- **Undo/Redo** — minimum 20 steps across all editors
- **Project save/resume** — all work auto-saved via SwiftData; resumable from home screen
- **iCloud + CloudKit sync** for projects (optional, free, opt-in)
- Share sheet: Photos app, Instagram, TikTok, Files, AirDrop, Messages
- Quick Share with platform-specific intent (Instagram URL scheme, TikTok intent)
- Watermark-free save (premium); watermark + optional ad (free)
- **App Intents** for Siri/Shortcuts/Spotlight: "Create Collage from Last 9 Photos", "New Story Carousel"
- **Widgets** (WidgetKit): "Recent Projects", "Photo of the Day"; interactive widget (iOS 17+) to start a new collage
- **Spotlight integration** — projects searchable by name and template category
- **Drag/Drop + Transferable** — drag photos from Files, Safari, Messages into the editor
- Localization: English + Spanish, French, German, Portuguese (BR), Japanese, Korean, Simplified Chinese, Hindi, Italian, Arabic

---

## 4. Technical Architecture

### 4.1 Tech Stack

| Layer | Technology | Rationale |
|-------|-----------|-----------|
| Language | **Swift 6** | Strict concurrency, async/await, type safety |
| UI — primary | **UIKit** | Editors, canvas, gestures, Metal/AVFoundation surfaces, scroll-heavy galleries — anything where 60fps precision and complex multi-touch matter. This is most of the app. |
| UI — secondary | **SwiftUI** | Settings, paywall, onboarding, mode selector, simple sheets/toasts, forms, App Intents UI. Required for **WidgetKit** (widgets must be SwiftUI). Used wherever it doesn't compromise gesture or rendering fidelity. |
| Rendering | **Metal** + **Core Image** | GPU-accelerated compositing; 60fps live preview |
| Video | **AVFoundation** | AVMutableComposition, AVAssetReader/Writer for lossless video assembly |
| AI / Vision | **VisionKit**, **Vision**, **Image Playground** | On-device subject lifting, segmentation, generative backgrounds |
| Persistence | **SwiftData** (iOS 17+) with Core Data fallback (iOS 16) | Projects, templates, saved assets |
| Cloud Sync | **CloudKit** private database | Optional cross-device project sync |
| Photo Access | **PhotosUI** (SwiftUI `PhotosPicker`) | No library permission required |
| Networking | **URLSession** (async/await) | Template CDN, premium asset downloads |
| Analytics | **TelemetryDeck** (privacy-first) | GDPR-compliant, no fingerprinting |
| Crash Reporting | **Firebase Crashlytics** | Industry standard, free tier sufficient |
| Monetization | **StoreKit 2** | Modern async API, App Store Server Notifications V2 |
| App Surface | **App Intents**, **WidgetKit**, **ActivityKit** | Shortcuts, widgets, Live Activities |
| Background Assets | **Background Assets framework** | Download premium template packs without bloating IPA |
| Testing | **XCTest** (unit + integration) + **XCUITest** (UI) | Built into Xcode; no third-party framework needed |
| CI/CD | **Xcode Cloud** or **GitHub Actions + Fastlane** | Automated TestFlight builds on every `develop` merge |
| Dependencies | **Swift Package Manager only** | No CocoaPods; clean, reproducible dependency graph |

### 4.1.1 UI Framework Strategy — Why UIKit Primary

Caroullage is a real-time photo and video editor with gesture-heavy canvases. The UI stack is therefore **UIKit-primary, SwiftUI-secondary** — not the other way around.

**Reasons UIKit owns the editor surfaces:**

1. **Composed multi-touch gestures.** Per-cell pan/zoom/rotate, simultaneously with canvas-level zoom, drag-to-swap between cells, bezier handle dragging, frame-strip reordering. UIKit's `UIGestureRecognizer` hierarchy with `require(toFail:)` and `shouldRecognizeSimultaneouslyWith` is the only mature toolkit for this; SwiftUI's gesture system still loses precision under composition.
2. **Direct CALayer / CAMetalLayer access.** The live compositor renders to a `CAMetalLayer`. UIKit hosts this natively; SwiftUI requires `UIViewRepresentable` wrappers that add lifecycle friction and hurt 60fps targets.
3. **AVFoundation surfaces.** `AVPlayerLayer`, custom `AVVideoCompositing`, `AVAssetResourceLoaderDelegate` are UIKit-native.
4. **Scroll + collection performance.** Template gallery, sticker grid, frame navigator, font picker — all do hundreds of thumbnail renders. `UICollectionView` with prefetching outperforms `LazyVGrid` materially at this scale.
5. **Swift 6 strict concurrency** is more battle-tested with UIKit hierarchies than with deeply nested SwiftUI view trees.
6. **Competitor reality.** SCRL, LiveCollage, Photoroom, CapCut, Photoleap are all UIKit-primary. There is a reason every chart-topping editor in this category landed there.

**Where SwiftUI is used (secondary):**

| Surface | Framework |
|---------|-----------|
| Settings, profile, support | SwiftUI |
| Paywall | SwiftUI |
| Onboarding slides (Step 06) | SwiftUI |
| Mode selector (entry screen) | SwiftUI |
| Toasts, banners, simple sheets | SwiftUI |
| App Intents snippet views | SwiftUI (required) |
| Widgets (`WidgetKit`) | SwiftUI (required) |
| Home screen project gallery | SwiftUI (uses `UIViewRepresentable` to wrap UIKit thumbnail collection) |
| **Grid / Polygon / Template / Carousel / Video editors** | **UIKit** |
| **All canvas/preview surfaces** | **UIKit + CAMetalLayer** |
| **Photo picker entry** | SwiftUI `PhotosPicker` (system-provided, works fine in either) |

**Interop pattern:**
- Top-level `SceneDelegate` + `UIWindow` is UIKit.
- Top-level navigation is `UINavigationController`.
- SwiftUI screens are pushed/presented via `UIHostingController`.
- UIKit editors embed SwiftUI subviews via `UIHostingController` for small interactive panels (filter strips, sliders, color pickers) where SwiftUI is genuinely simpler.
- Communication crosses via plain Swift `@Observable` classes — no `@EnvironmentObject` plumbing through the bridge.

**Implementation discipline:**
Implementations stay simple and concise. We do not build a custom layout system on top of UIKit; we use Auto Layout + programmatic constraints (`NSLayoutAnchor`). Cells, navigator strips, and collections use `UICollectionViewCompositionalLayout`. Nothing in this stack requires reinventing a wheel.

### 4.2 Minimum Deployment Target
**iOS 16.0** — Matches SCRL (quality benchmark). Covers ~95%+ of active iOS devices.

**iOS 17+ feature gating:**
- VisionKit `subjectLift` → graceful "Update to iOS 17 to use this" message on iOS 16
- Interactive widgets → static widget fallback on iOS 16
- Image Playground (iOS 18.2+) → hidden if unavailable; not promoted as a paid feature

**Xcode + SDK:** Xcode 26 + iOS 26 SDK (required by Apple for App Store submissions since April 2026).

### 4.3 Architecture Pattern: MVVM-C (MVVM + Coordinator)

UIKit-primary apps are best served by the **Coordinator pattern** for navigation. Each major flow has a coordinator that owns its `UINavigationController` stack and the view models for its screens. SwiftUI screens are presented via `UIHostingController` from the coordinator.

```swift
// Example coordinator skeleton
final class GridEditorCoordinator {
    private let navigationController: UINavigationController
    private let project: CollageProject

    func start() {
        let vm = GridEditorViewModel(project: project)
        let vc = GridEditorViewController(viewModel: vm)  // UIKit
        vc.onExportRequested = { [weak self] in self?.presentExportSheet() }
        navigationController.pushViewController(vc, animated: true)
    }

    private func presentExportSheet() {
        let exportView = UniversalExportSheetView(...)  // SwiftUI
        let host = UIHostingController(rootView: exportView)
        host.modalPresentationStyle = .pageSheet
        navigationController.present(host, animated: true)
    }
}
```

```
App
├── Core/
│   ├── Models/                # SwiftData: Project, CollageCell, Template, Asset
│   ├── Services/
│   │   ├── TemplateService.swift          # Load, cache, download templates
│   │   ├── ExportService.swift            # Unified export (image + video)
│   │   ├── PurchaseService.swift          # StoreKit 2 subscriptions
│   │   ├── CarouselService.swift          # Panoramic stitch, frame split logic
│   │   ├── AIService.swift                # VisionKit, Vision, Image Playground wrappers
│   │   ├── CloudSyncService.swift         # CloudKit project sync (optional)
│   │   └── LiveActivityService.swift      # Export progress on Lock Screen
│   ├── Rendering/
│   │   ├── CollageRenderer.swift          # Metal compositor
│   │   ├── PolygonLayoutEngine.swift      # CGPath geometry for shapes
│   │   ├── PanoramicStitcher.swift        # vImage frame split / stitch
│   │   ├── VideoComposer.swift            # AVFoundation pipeline
│   │   └── WatermarkRenderer.swift        # Free-tier watermark
│   ├── Intents/                # App Intents (Siri, Shortcuts, Spotlight)
│   ├── Widgets/                # WidgetKit extensions
│   └── Extensions/
│
├── Coordinators/               # Navigation flow controllers (UIKit MVVM-C)
│   ├── AppCoordinator.swift
│   ├── HomeCoordinator.swift
│   ├── GridEditorCoordinator.swift
│   ├── TemplateCoordinator.swift
│   ├── CarouselCoordinator.swift
│   └── VideoCoordinator.swift
│
├── Features/
│   ├── Home/                   # Project gallery — SwiftUI shell wrapping UIKit thumbnail collection
│   ├── ModeSelector/           # SwiftUI — entry: choose Pillar 1, 2, or 3
│   ├── GridEditor/             # UIKit — Pillar 1: geometric grid + polygon editor
│   │   ├── GridEditorViewController.swift
│   │   ├── GridEditorViewModel.swift
│   │   ├── CanvasView.swift            # UIView hosting CAMetalLayer
│   │   ├── CellGestureController.swift # UIGestureRecognizer composition
│   │   └── Panels/                     # SwiftUI sub-panels via UIHostingController
│   │       ├── FilterStripView.swift
│   │       └── BackgroundPickerView.swift
│   ├── TemplateGallery/        # UIKit — UICollectionView with diffable data source
│   ├── TemplateEditor/         # UIKit — frame/story/text editor
│   ├── CarouselEditor/         # UIKit — multi-frame carousel builder
│   │   ├── CarouselEditorViewController.swift
│   │   ├── FrameNavigatorView.swift     # UICollectionView strip
│   │   ├── CarouselPreviewViewController.swift
│   │   └── PanoramicStitcherViewController.swift
│   ├── VideoEditor/            # UIKit — AVPlayerLayer-backed preview, timeline scrubbers
│   ├── AI/                     # UIKit canvas hosts; SwiftUI for prompt-input modals
│   ├── Export/                 # SwiftUI — UniversalExportSheet (form-style UI)
│   ├── Onboarding/             # SwiftUI (added in Step 06)
│   ├── Paywall/                # SwiftUI (added in Step 06)
│   └── Settings/               # SwiftUI
│
├── Resources/
│   ├── Templates/              # Bundled JSON template definitions
│   ├── CarouselTemplates/      # Bundled carousel template definitions
│   ├── Fonts/
│   ├── Stickers/
│   └── Assets.xcassets
│
└── Tests/
    ├── Unit/
    ├── Integration/
    └── UI/
```

### 4.4 Rendering Pipeline

```
User Gesture → ViewModel (state mutation)
                      ↓
        CollageLayoutEngine
        (cell frames + CGPaths + polygon masks)
                      ↓
        Metal Compositor
        (renders cells as MTLTextures → composite bitmap)
                      ↓
        SwiftUI Image (60fps preview)  /  CGImage (export to disk)
```

**Carousel panoramic stitch pipeline:**
```
Wide source photo(s)
        ↓
PanoramicStitcher (vImage)
        ↓
Divide into N equal-width frames
        ↓
Edge-align verification (pixel diff check, 0 tolerance)
        ↓
Per-frame CGImage array → CollageRenderer per frame
        ↓
Numbered export ZIP or video slideshow
```

**Video collage pipeline:**
```
Video assets per cell
        ↓
AVMutableComposition (timeline assembly)
Photo cells → CMSampleBuffer (CVPixelBuffer)
        ↓
AVVideoCompositionCoreAnimationTool (transitions + overlays)
        ↓
AVAssetWriter (H.264 / HEVC) → Camera Roll
        ↓
Live Activity updates progress to Lock Screen / Dynamic Island
```

**AI pipeline (subject lift example):**
```
Source UIImage
        ↓
VisionKit ImageAnalyzer (iOS 17+)
        ↓
analyzer.subjects → primary subject CGImage with alpha
        ↓
Added to current canvas as a sticker overlay (or cell content)
```

---

## 5. Monetization Strategy

*Full monetization implementation lives in Part 2 (Deployment). This section defines the model so the development team knows what gates to wire up.*

### 5.1 Free vs. Premium Tiers

**Free (no account required):**
- All 3 creative modes accessible (grid, template/carousel, video)
- 15 grid templates + 5 polygon templates
- 10 frame templates + 3 carousel templates
- Video collage (up to 3 cells, 1080p)
- All on-device AI features (subject lift, magic eraser, AI auto-layout) — generous free tier
- Export with small watermark
- Max 1 interstitial ad per export session

**Premium subscription (no watermark, all templates, full features):**
- All 150+ templates + all carousel types (monthly updates)
- All polygon shapes + custom bezier editor
- 4K video export + HEVC
- Carousel export as video slideshow
- Image Playground generative backgrounds (uses Apple Intelligence)
- Unlimited undo history
- Unlimited project saves + CloudKit sync
- Priority new features

### 5.2 Pricing

| Plan | Price | Notes |
|------|-------|-------|
| Weekly | $2.99/week | Impulse entry point |
| Monthly | $4.99/month | Core conversion target |
| Yearly | $24.99/year | Best value (~$2.08/month) — **default selection** |
| Lifetime | $49.99 one-time | Early adopter / gifting |

*Avoid the $7.99/week trap — Blur Photo Editor reviews confirm aggressive pricing immediately damages ratings. Annual-default + visible weekly decoy is the 2024–2026 chart-topper pattern.*

### 5.3 StoreKit 2 Implementation Notes
- `Product.products(for:)` async API
- App Store Server Notifications V2 for real-time subscription state
- Introductory offer: 7-day free trial on yearly plan
- Family Sharing enabled on all plans
- Trial-end reminder local notification scheduled during onboarding

---

## 6. Unit Testing Strategy

### 6.1 Philosophy: Learn as You Go

You don't need to know everything about testing upfront. The strategy below introduces tests incrementally — one type per phase. By the time you reach Step 05 (Polish), you'll have written tests naturally throughout development and will have a solid foundation without it ever feeling overwhelming.

**Golden rule:** Write tests for the code you're most afraid to break. Start there.

### 6.2 What is a Unit Test? (Quick Primer)

A unit test is a small function that checks one specific behavior:
```swift
// Tests/Unit/CollageLayoutEngineTests.swift
func testTwoCellGridProducesEqualHalves() {
    let engine = CollageLayoutEngine()
    let cells = engine.layout(for: .twoUp, canvasSize: CGSize(width: 100, height: 100))
    XCTAssertEqual(cells[0].frame.width, 50)
    XCTAssertEqual(cells[1].frame.width, 50)
}
```
That's it. `XCTAssertEqual` checks that the result matches what you expect. If it doesn't, the test fails and Xcode highlights the line.

### 6.3 Test Types You'll Use

| Type | Tool | When to write | What it tests |
|------|------|--------------|---------------|
| **Unit test** | XCTest | Steps 00–05 | Pure Swift logic: geometry, models, parsers |
| **Integration test** | XCTest | Steps 02–05 | Two components working together (e.g., TemplateService + SwiftData) |
| **UI test** | XCUITest | Step 05 | User flows end-to-end: "tap New Project → select photo → export" |
| **Snapshot test** (optional) | `swift-snapshot-testing` (SPM) | Steps 03–05 | Rendered collage output matches a reference image |

### 6.4 What to Test in Each Step

Each Development step file (`Step_NN_*.md`) ends with a **Unit Tests** section listing the exact tests to write for that step. The progression is:

- **Step 00** — No tests yet; just confirm the test target builds and empty suite passes.
- **Step 01** — Grid layout geometry (pure functions, ideal first target).
- **Step 02** — Polygon paths + template JSON parsing.
- **Step 03a** — Template service integration.
- **Step 03b** — Carousel stitcher and frame logic.
- **Step 04** — Video composer and universal export.
- **Step 05** — AI features + polish; UI tests for 3 critical flows.

### 6.5 Coverage Target

Don't aim for 100% — that's a distraction. Aim for:
- **Core rendering engine:** ~80% coverage (logic bugs here hurt users most)
- **Template/carousel parsers:** ~70% coverage
- **AI service wrappers:** ~50% coverage (mostly integration with Apple APIs)
- **UI layer:** ~20% coverage (just the 3 critical flows)

Xcode shows coverage in the Report Navigator after running tests with coverage enabled.

---

# PART 1 — DEVELOPMENT (Primary)

The bulk of the project. Six steps that build the working app from empty Xcode project to feature-complete, polished, simulator-ready application.

---

## 7. Development Phases

### Step 00 — Project Setup (Weeks 1–2)
Stand up Xcode project, Git, CI/CD, tooling, SwiftData schema, StoreKit local config, dependencies. No features yet — only foundation. Any developer can clone, run one command, and be ready to code.

**Key deliverables:**
- Xcode project (iOS 16.0+, Swift 6, SwiftUI) with Debug/Staging/Release configs
- Git repo with branch protection, SwiftLint, SwiftFormat
- CI/CD: Xcode Cloud or GitHub Actions running on every PR
- Fastlane Match for codesigning
- SwiftData stub models (CollageProject, CollageCell, etc.)
- Template + carousel JSON schemas
- StoreKit local config for testing
- Crashlytics + TelemetryDeck initialized

### Step 01 — Grid Collage (Weeks 3–7)
Build the rectangular grid editor — the foundation every other editor reuses.

**Key deliverables:**
- `CollageLayoutEngine` (8 grid types, pure functions)
- Metal compositor with 60fps live preview
- `PhotosPicker` (SwiftUI) integration
- Per-cell pan/zoom/rotate + filter strip
- Border/gap/corner radius controls
- Undo/Redo (20-step stack)
- Auto-save + resume (SwiftData)
- Basic image export (to be upgraded in Step 04)
- 8 unit tests on layout engine

**Milestone:** Internal build with working rectangular grid editor + passing unit tests.

### Step 02 — Polygon & Shape Collage (Weeks 8–12)
Extend the grid editor with non-rectangular cells.

**Key deliverables:**
- Polygon layout engine (9 named shapes + custom bezier)
- Metal stencil clipping for non-rectangular cells
- 10 polygon templates
- Custom bezier editor (premium-gated)
- Polygon support in template JSON parser
- 12 unit tests (polygon + parser)

**Milestone:** Pillar 1 complete. Internal alpha build.

### Step 03 — Template & Carousel Collage (Weeks 13–22)
The largest step; split into two sub-steps because the carousel system is substantial.

**Step 03a — Standard Templates (Weeks 13–17):**
- `TemplateService` (bundled + cached templates)
- Template gallery UI (categories, search, thumbnails)
- Text zone editor (font, color, alignment, spacing, opacity)
- Sticker system (3 bundled packs, 60 stickers total)
- Freeform canvas with snap guides
- 30 curated standard templates
- 3 template service integration tests

**Step 03b — Carousel Mode (Weeks 18–22):**
- `CarouselService` + `PanoramicStitcher` (vImage)
- All 4 carousel types (panoramic, matched, scroll-through, grid-preview)
- Frame navigator (reorder, add, delete)
- Sync edit toggle
- Carousel preview player with swipe physics
- Safe-zone overlay (IG/TikTok UI guides)
- 20 curated carousel templates
- Carousel-specific export (ZIP + video slideshow)
- 10 unit + integration tests

**Milestone:** Pillars 1 + 2 complete. Internal alpha includes carousel.

### Step 04 — Video Collage + Universal Export (Weeks 23–30)
Two deliverables in one step: video editing + the unified export system that updates every prior editor.

**Key deliverables:**
- `VideoComposer` (direct `AVAssetReader/Writer` pipeline)
- Video cells: trim, loop, mute, per-cell volume
- Animated transitions (crossfade, slide, zoom)
- Background music + auto-beat-sync via `AVAudioEngine`
- Live Photo / motion sticker import
- **Universal Export System** (`UniversalExportSheet`):
  - Platform presets: Instagram Post / Story, TikTok, YouTube, X, WhatsApp, Print, Custom
  - Auto-baked overlays in video output (text, stickers, filters, transitions)
  - Save to Photos / Quick Share / Files
  - Progress indicator + cancel for video exports
  - Live Activity on Lock Screen during video export
- All prior editors updated to use `UniversalExportSheet`
- 6 integration tests on export

**Milestone:** Pillars 1 + 2 + 3 + unified export complete.

### Step 05 — AI Features & Final Polish (Weeks 31–35)
Add the AI features that table-stake a chart-topping app in 2026, then polish.

**Key deliverables:**
- `AIService` wrapping VisionKit, Vision, Image Playground
- Subject lifting (VisionKit `subjectLift`, iOS 17+)
- Magic eraser (Vision segmentation + Core Image inpainting)
- AI auto-layout (saliency-driven cell composition)
- Generative backgrounds (Image Playground, iOS 18.2+)
- Photo→sticker workflow
- Smart template suggestions (Vision metadata analysis)
- App Intents: "Create Collage from Last 9 Photos", "New Story Carousel"
- WidgetKit: "Recent Projects" + "Photo of the Day" widget
- Spotlight indexing of saved projects
- iCloud + CloudKit project sync (opt-in)
- Drag/Drop + Transferable from Files, Safari, Messages
- Home screen polish (project gallery, empty state, sort/filter)
- Final UI/UX pass on all editors
- 3 critical UI tests (`XCUITest`)
- Code coverage report meeting targets

**Milestone:** Feature-complete, fully polished app running end-to-end in the simulator. Indistinguishable from a top-chart competitor in terms of features and UX.

> **DEVELOPMENT IS COMPLETE.** The app works. Every feature is built. Every test passes. The simulator demo is impressive enough to show investors. Time to ship.

---

# PART 2 — DEPLOYMENT (Secondary, Essential)

The work that turns the finished app into a live App Store product. This is one step, but it is dense — monetization, paywall, onboarding funnel, localization, accessibility, App Store assets, Featuring nomination, compliance, and post-launch monitoring.

Do not start this until Part 1 is 100% done.

---

### Step 06 — Deployment: Monetization, Compliance, Launch (Weeks 36–42)

**Phase 6.1 — StoreKit 2 Subscriptions**
- `PurchaseService` (entitlement source of truth)
- Load products, handle purchase + restore, listen to `Transaction.updates`
- App Store Server Notifications V2 endpoint
- Family Sharing enabled on all products
- 7-day free trial on yearly plan
- Local notification scheduled for trial-end day

**Phase 6.2 — Paywall**
- `PaywallView` shown when free user taps a premium feature
- Annual-default selection, weekly framed as worse value
- 5 feature bullets, "Best Value" badge on yearly
- Restore Purchases + Terms + Privacy Policy links
- Apple-compliant subscription confirmation (price + renewal terms)

**Phase 6.3 — Onboarding Funnel**
- 4–6 swipeable value slides
- 1 personalization question (use case: Instagram / TikTok / Pinterest / Other)
- Permission priming screen *before* iOS prompt (massively reduces deny rate)
- Gallery preview using user's own photos as last beat before paywall
- "Hard paywall after value preview" pattern (industry default 2024–2026)
- `hasSeenOnboarding` flag in UserDefaults

**Phase 6.4 — Localization (11 Languages Day 1)**
- English + Spanish, French, German, Portuguese (BR), Japanese, Korean, Simplified Chinese, Hindi, Italian, Arabic
- All `Localizable.strings` keys translated
- RTL layout support for Arabic (test every screen)
- Localized App Store metadata for all 11

**Phase 6.5 — Accessibility**
- VoiceOver labels on every interactive element
- Dynamic Type on all text
- Minimum 44×44pt tap targets
- Color contrast ≥ 4.5:1 on body text
- Reduce Motion honored
- Apple Editorial team specifically checks accessibility for featuring

**Phase 6.6 — App Store Compliance (2026 Requirements)**
- `PrivacyInfo.xcprivacy` with required reason declarations:
  - `UserDefaults` (CA92.1)
  - `fileTimestamp` (C617.1) — PhotoKit pipelines
  - `diskSpace` (E174.1) — video export
  - `systemBootTime` (if used)
- All third-party SDK privacy manifests + signatures present (Firebase, etc.)
- `NSUsageDescription` strings audited (Photo Library, Microphone)
- Account deletion in-app if sign-in offered (Guideline 5.1.1)
- DSA Trader status declared in App Store Connect (EU requirement)
- Age Rating questionnaire (new 2026 system) completed
- No private API usage — verify with `otool -L`
- IDFA NOT linked (no ad SDK)

**Phase 6.7 — App Icon, Screenshots & Assets**
- Final 1024×1024 app icon (no alpha) in Assets.xcassets
- Screenshots for **6.7" iPhone 16 Pro Max** (5 required):
  - Hero — carousel preview (swipe animation)
  - Grid + polygon shapes
  - Template gallery
  - Video collage
  - AI features (subject lift / generative background)
- Screenshots for **12.9" iPad Pro** (strongly recommended)
- 3 App Preview videos (30s each, vertical) — increases conversion ~20%
- Localized screenshots for all 11 languages

**Phase 6.8 — Watermark System**
- `WatermarkRenderer` bakes "Made with Caroullage" into free exports
- No watermark for premium users
- Watermark on exported file only, not in-app preview

**Phase 6.9 — Rating Prompt**
- `SKStoreReviewRequest` after first successful export only
- Never on launch, never after error
- Guarded by `totalExportCount == 1`

**Phase 6.10 — Performance Profiling**
- Instruments → Allocations: peak < 200 MB on video editing (iPhone 12)
- Instruments → Core Animation: 60fps on iPhone 13+
- Instruments → Leaks: 0 leaks on full cycle
- Cold launch < 2.0s on iPhone 13

**Phase 6.11 — App Store Connect Setup**
- App name, subtitle, description, keywords (all 11 languages)
- ASO keyword strategy: avoid "collage" alone (Pic Stitch owns it); target intent verticals — "instagram carousel maker", "photo grid for ig", "reels collage", "photo dump maker"
- Support URL: `https://devron.com/support/caroullage`
- Privacy Policy URL: `https://devron.com/legal/caroullage/privacy.html`
- Content rights: confirm all fonts, stickers, templates licensed
- Review notes: explain subscription model + free tier capabilities

**Phase 6.12 — Pre-Launch Growth**
- **Featuring Nomination** in App Store Connect — submit minimum 2 weeks, ideally 12 weeks before launch. Tie pitch to platform hero feature (Image Playground / Live Activities / Action Button)
- **Pre-orders** — set up in App Store Connect (one of the few ways to accumulate downloads before launch)
- **In-App Event** scheduled for launch week ("Launch Week templates drop")
- **TestFlight cohorts:**
  - Closed creator beta: 50–200 IG/TikTok creators (5k–50k followers), lifetime Pro in exchange for content + reviews
  - Public TestFlight link: posted to r/iOSBeta, Indie Hackers, Product Hunt Ship
- **Apple Search Ads** — bid on competitor brand terms (SCRL, Pic Stitch, Unfold, Mojo) from day 1
- **Creator seeding** — pay micro-creators $200–$1,000/post for "before/after" content
- **Product Hunt launch** — Tuesday or Wednesday, assets pre-staged

**Phase 6.13 — Submission**
- Version `1.0.0 (1)` set
- Archive with Release scheme
- Validate in Xcode Organizer (0 errors)
- Upload to App Store Connect
- All metadata + screenshots complete in 11 languages
- Submit for App Review
- Respond to any reviewer feedback within 24h

**Phase 6.14 — Post-Launch Monitoring (First 30 Days)**
- Crashlytics: day-1 crash-free rate ≥ 99.5%
- App Store rating: target ≥ 4.6 average
- StoreKit analytics: trial-to-paid conversion target ≥ 25%
- Respond to every App Store review within 48 hours
- Daily monitoring of subscription churn, refund rate, top complaints
- v1.1 planning based on review feedback + analytics

**Phase 6.15 — Ongoing (Post-30-Days)**
- 10 new templates/month (mix of standard + carousel)
- Seasonal template drops (holiday, summer, back-to-school)
- Push notification campaigns for new template packs
- A/B test paywall pricing via StoreKit promotional offers
- iPad layout optimization
- macOS Catalyst consideration

---

## 8. Version Control & Team Workflow

### 8.1 Repository Structure

```
Caroullage/
├── Caroullage.xcodeproj
├── Caroullage/                  # Main app target
├── CaroullageWidgets/           # WidgetKit extension
├── CaroullageIntents/           # App Intents extension
├── CaroullageTests/
│   ├── Unit/
│   ├── Integration/
│   └── UI/
├── Packages/                       # Local Swift packages
│   ├── CollageCore/                # Rendering engine (isolated, testable)
│   ├── TemplateKit/                # Template + carousel JSON parser/renderer
│   └── VideoComposer/              # AVFoundation pipeline
├── Fastlane/
│   ├── Fastfile
│   └── Matchfile
├── .github/workflows/              # or .xcode-cloud/
├── .swiftlint.yml
├── .swiftformat
└── README.md
```

### 8.2 Branching Strategy

| Branch | Purpose |
|--------|---------|
| `main` | Production only. Tagged releases. No direct push — PR required. |
| `develop` | Integration. All features merge here first. CI runs on every PR. |
| `feature/CC-XXX-description` | Feature work, branched from `develop` |
| `fix/CC-XXX-description` | Bug fixes |
| `release/X.Y.Z` | Release prep — only bug fixes, no new features |
| `hotfix/CC-XXX-description` | Emergency fix branched directly from `main` |

### 8.3 Commit Convention (Conventional Commits)

```
feat(carousel): add panoramic frame stitcher
feat(grid): add hexagonal cell split
feat(ai): add VisionKit subject lift to cell editor
fix(video): resolve AVExportSession quality degradation on HEVC
test(layout): add unit tests for 3-cell grid geometry
chore(ci): update Xcode Cloud workflow for iOS 26 sim
docs(readme): add project setup instructions
```

### 8.4 CI/CD Pipeline

**On every PR to `develop`:**
1. SwiftLint lint check (fails build on errors)
2. Build (Debug scheme)
3. Unit + integration tests
4. UI tests (iPhone 16 simulator, headless)

**On merge to `develop`:**
1. Release build
2. Full test suite
3. Auto-deploy to TestFlight (internal group)

**On `release/X.Y.Z` → `main`:**
1. Full test suite
2. Archive + IPA export
3. Upload to App Store Connect via Fastlane `deliver`
4. Create GitHub release tag + changelog

### 8.5 Code Signing (Fastlane Match)

```ruby
# Matchfile
git_url("git@github.com:Al-ImranRony/ios-certs-private.git")
app_identifier("com.devron.caroullage")
username("dev3@devron.com")
```

Each developer/machine runs `fastlane match development` once. No manual certificate management.

### 8.6 Build Environments

| Environment | Scheme | Use |
|------------|--------|-----|
| Development | Debug | Local dev, debug logging, StoreKit local config |
| Staging | Staging | TestFlight internal, staging CDN |
| Production | Release | App Store, live CDN, real StoreKit |

---

## 9. Data Models

### 9.1 SwiftData Schema

```swift
@Model class CollageProject {
    var id: UUID
    var createdAt: Date
    var updatedAt: Date
    var mode: CollageMode       // .grid, .template, .carousel, .video
    var canvasSize: CGSize
    var templateID: String?
    var carouselType: CarouselType?   // .panoramic, .matched, .scrollThrough, .gridPreview
    var frameCount: Int               // for carousel mode
    var cells: [CollageCell]
    var previewThumbnail: Data?       // JPEG thumbnail for home gallery
    var exportSettings: ExportSettings
}

@Model class CollageCell {
    var id: UUID
    var index: Int              // position in grid or frame index in carousel
    var frameIndex: Int?        // carousel: which frame this cell belongs to
    var shape: CellShape        // .rectangle, .diagonal, .triangle, .hexagon, .custom
    var layoutFrame: CGRect     // normalized 0.0–1.0 coordinates
    var photoAssetID: String?   // PHAsset local identifier
    var videoAssetID: String?
    var transform: CellTransform    // pan, zoom, rotation applied to media
    var filters: CellFilters        // brightness, contrast, saturation, warmth, sharpness
    var borderWidth: CGFloat
    var cornerRadius: CGFloat
    var textOverlays: [TextOverlay]
}

enum CarouselType: String, Codable {
    case panoramic
    case matched
    case scrollThrough
    case gridPreview
}
```

### 9.2 Template JSON Schema (Standard)

```json
{
  "id": "minimal-2up-horizontal",
  "name": "Minimal 2-Up",
  "category": "minimal",
  "isPremium": false,
  "canvasAspectRatio": "1:1",
  "cells": [
    {
      "id": "cell-1",
      "type": "photo",
      "frame": { "x": 0.0, "y": 0.0, "width": 0.5, "height": 1.0 },
      "shape": "rectangle",
      "borderWidth": 2.0
    },
    {
      "id": "cell-2",
      "type": "photo",
      "frame": { "x": 0.5, "y": 0.0, "width": 0.5, "height": 1.0 },
      "shape": "rectangle",
      "borderWidth": 2.0
    }
  ],
  "background": { "type": "solid", "color": "#FFFFFF" }
}
```

### 9.3 Carousel Template JSON Schema

```json
{
  "id": "travel-panoramic-3",
  "name": "Travel Panoramic",
  "category": "travel",
  "isPremium": true,
  "carouselType": "panoramic",
  "canvasAspectRatio": "4:5",
  "frameCount": 3,
  "frames": [
    {
      "index": 0,
      "cells": [
        {
          "id": "frame0-photo",
          "type": "photo",
          "frame": { "x": 0.0, "y": 0.0, "width": 1.0, "height": 0.8 }
        },
        {
          "id": "frame0-text",
          "type": "text",
          "frame": { "x": 0.05, "y": 0.82, "width": 0.9, "height": 0.15 },
          "defaultText": "Your caption here",
          "fontStyle": "headline"
        }
      ]
    }
  ],
  "panoramicSource": {
    "splitAxis": "horizontal",
    "overlapPixels": 0
  },
  "background": { "type": "solid", "color": "#1A1A1A" }
}
```

---

## 10. Performance Targets

| Metric | Target | Test Device |
|--------|--------|-------------|
| App launch (cold) | < 2.0s | iPhone 13 |
| Editor load | < 0.5s | iPhone 13 |
| Live preview frame rate | 60 fps | iPhone 13+ |
| Photo import (10 photos) | < 1.5s | iPhone 13 |
| Carousel panoramic stitch (6 frames) | < 3.0s | iPhone 13 |
| Subject lift (VisionKit) | < 1.5s | iPhone 13 |
| 1080p video export (30s collage) | < 45s | iPhone 13 |
| App memory during video editing | < 200 MB | iPhone 12 (4 GB) |
| App binary size | < 150 MB | — |
| Test suite total runtime | < 60s | CI simulator |

---

## 11. App Store Launch Strategy

*Detailed launch tactics live in Step 06 (Deployment). High-level positioning:*

### 11.1 ASO Keywords
- Avoid: `collage` (Pic Stitch owns it)
- Target intent verticals: `instagram carousel maker`, `photo grid for ig`, `reels collage`, `photo dump maker`, `story template`, `panoramic carousel`

### 11.2 Screenshot Plan (6.7" iPhone 16 Pro Max)
- Screen 1: Hero — carousel preview swipe animation — "Create stunning Instagram carousels"
- Screen 2: Grid + polygon shapes — "Geometric layouts that stand out"
- Screen 3: Template gallery — "200+ hand-crafted templates"
- Screen 4: Video collage — "Mix photos and videos seamlessly"
- Screen 5: AI features — "One-tap background removal + generative AI"

### 11.3 Rating Strategy
- `SKStoreReviewRequest` after first successful export — never on first launch, never after an error
- Respond to every App Store review within 48 hours
- Target 4.7+ average by launch + 30 days

---

## 12. Risk Register

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| Video export quality degradation | Medium | High | Direct AVAssetReader/Writer pipeline; pixel-compare integration test |
| Memory pressure during video editing | High | High | Stream frames; never load full video to RAM; test on iPhone 12 (4 GB) |
| Panoramic stitch edge misalignment | Medium | Medium | Unit test edge pixel comparison; 0px tolerance |
| App binary size > 150 MB | Medium | Medium | Background Assets framework for premium template packs |
| Aggressive paywall → bad reviews | Low | High | Generous free tier; annual-default pricing |
| AVFoundation API changes (iOS 27+) | Low | Medium | Modern non-deprecated APIs throughout |
| StoreKit receipt edge cases | Low | High | App Store Server Notifications V2; local StoreKit test config |
| iOS 17 AI features broken on iOS 16 devices | Medium | Low | Graceful "Update iOS to use this" fallback; AI gated by capability check |
| Image Playground unavailable on non-Apple-Intelligence devices | High | Low | Feature hidden when unavailable; not the only premium feature |
| App Review rejection for compliance | Medium | High | Pre-submission audit of all 2026 requirements (privacy manifest, age rating, DSA) |

---

## 13. Immediate Next Steps (Before Writing Code)

1. **Register** bundle ID `com.devron.caroullage` in App Store Connect
2. **Create GitHub repo** `Al-ImranRony/Caroullage` with branch protection on `main` and `develop`
3. **Submit Featuring Nomination** in App Store Connect (12 weeks before launch — start early)
4. **Create Xcode project** (iOS 16.0, Swift 6, Xcode 26+, **Storyboard App template** — we delete the storyboard and wire a programmatic `SceneDelegate` per Step 00; UIKit is primary)
5. **Spike: Metal compositor** — validate 60fps live preview on iPhone 13 with a dummy 4-cell layout
6. **Spike: Carousel panoramic stitch** — verify `vImage` can split a 4000×5000px image into 5 frames with pixel-perfect edges in < 3s
7. **Spike: VisionKit subjectLift** — confirm one-tap subject extraction works on a sample photo in < 1.5s
8. **Design wireframes** for: Home, Mode selector, Grid editor, Carousel editor (navigator + preview), AI feature surfaces
9. **Define the 15 rectangular grid templates** as JSON files
10. **Define the 5 launch carousel templates** as JSON files (1 panoramic, 2 matched, 1 scroll-through, 1 grid-preview)
11. **Run Step 00 setup checklist** (CI/CD, Fastlane, SwiftLint, test target)

---

*This is the final pre-development plan. Part 1 (Development) is the primary, multi-month effort. Part 2 (Deployment) is the launch sprint after Development completes. Update this plan at the start of each step with architectural decisions made, timeline revisions, and any new requirements discovered. Keep it in Git alongside the source code.*
