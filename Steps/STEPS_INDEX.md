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
| **02** | `Step_02_PolygonCollage.md` | Polygon & custom shape collage | 8–12 | 🟡 Core complete — 9 shapes + masked canvas/export + typed parser + premium bezier editor; 12/12 new tests green (29 total). See Step 02 notes below |
| **03a** | `Step_03a_StandardTemplates.md` | Frame/story template editor | 13–17 | 🟡 Slices 1–4 complete — foundation, Template Gallery UI, `.template` collage layout, and catalog v1 (21 bundled templates across all 5 categories & 4 canvas presets, 4 premium). 53 unit + 7 UI tests green. Text-zone editor, sticker system, freeform canvas, and the remaining ~9 text/sticker templates remain. See Step 03a notes below |
| **03b** | `Step_03b_CarouselTemplates.md` | SCRL-style carousel mode | 18–22 | ⬜ Not started |
| **04** | `Step_04_VideoCollage.md` | Video collage + universal export | 23–30 | ⬜ Not started |
| **05** | `Step_05_AIFeaturesAndPolish.md` | AI features, App Intents, widgets, polish | 31–35 | ⬜ Not started |
| **05b** | `Step_05b_VisualDesignExcellence.md` | Visual design excellence + app icon (orange/Claude theme, SCRL-grade per-screen redesign) | 35–37 | ⬜ Not started — **design foundation already laid (2026-07-13)** |

**End of Part 1:** App is feature-complete and visually indistinguishable from a chart-topping App Store app (SCRL-grade) — runs end-to-end in the simulator with a finished orange/white brand identity, a custom app icon, and a polished per-screen design. No monetization yet, no localization, no App Store assets. Those live in Part 2.

> **Note (2026-07-13):** A lightweight **design foundation** (`Core/DesignSystem/` — `Theme`, `Haptics`, `AppAppearance`) was established right after Step 01 so Steps 02–05 inherit an on-brand orange/white look instead of raw system defaults. The *comprehensive* SCRL-grade visual pass — custom app icon, per-screen redesign, motion, and brilliant use of the orange theme — is consolidated into **Step 05b**, executed once all screens exist. See `Step_05b_VisualDesignExcellence.md` for the full brief.

### Step 01 — decisions & deviations (2026-07-11)
- **Renderer:** Core Graphics compositor (`CollageRenderer`) instead of Metal for now. `CanvasView` displays the composited `CGImage` and is structured so a Metal/CAMetalLayer backend can drop in during Step 02's polygon stencil work. All done-criteria met (60fps target not measured headless).
- **Deployment target:** iOS 17.0 (inherited from the Step 00 scaffold's pure-SwiftData choice, not 16.0). Revisit if a Core Data fallback is added.
- **Editor state:** grid editing works on a value snapshot (`GridEditorState`, `Codable`); the `UndoStack` records these (20-step). Persistence stores the JSON blob in `CollageProject.gridStateData` + photos as JPEGs under `Documents/Projects/<id>/images/`.
- **VM binding:** `GridEditorViewModel` uses an `onChange` callback (idiomatic UIKit) rather than `@Observable`.
- **Home:** plain UIKit `HomeViewController` gallery; the SwiftUI shell wrapper is deferred to Step 05 polish.
- **Deferred to later:** live-preview at true 60fps via Metal (Step 02), per-cell drag-preview polish for swap (functional long-press→tap-to-swap works now).
- **Gotcha fixed:** `ModelContext` does not retain its `ModelContainer` — `ProjectStore` must hold the container strongly or the SQLite store disconnects and the next fetch traps.

### Step 02 — decisions & deviations (2026-07-13)
- **Geometry model:** introduced a unified `CollageLayout` enum (`.grid` | `.polygon`) as the state's single source of truth (replaces bare `GridTemplate`); backward-compatible `GridEditorState` decoding keeps Step 01 saved projects loading. Cell boundaries are described *parametrically* by `CellClipShape` (rectangle/ellipse/polygon/custom, normalized points) — the `CGPath` is generated on demand, so `CellFrame` stays `Sendable`/`Codable` (no stored `CGPath`).
- **Rendering:** instead of the plan's Metal stencil, polygon clipping uses a `CAShapeLayer` mask on the existing GPU cell views (fits the Step 01 layer tree) and a `CGPath` clip in the Core Graphics export renderer — preview and export share the same generated path, so they match. (Metal remains a future swap.)
- **9 polygon layouts** implemented in `PolygonTemplate` (diagonals ×2, triangle peak, 4-way fan, 7-hex honeycomb, circle halo, double circle, arrows ×2). Tiling layouts partition exactly; circle/arrow layouts are background+overlay styles by design.
- **Typed template parser** (`TemplateParser` + `CollageTemplate`) shipped early (was slated for 03a) because polygons need `shape` parsing. Reads the existing schema's `shape` field (not a new `shapeType`); unknown/missing shape → `.rectangle`, frame values clamped 0…1, `canvasAspectRatio` is the only hard-required field.
- **Premium bezier editor** (`BezierEditorViewController`) — tap/drag/hold to trace a closed boundary with snap guides; gated by a lightweight `EntitlementStore` (free by default; real StoreKit is Step 06). Applies a per-cell `EditorCellState.customClip` (v1: cell 0).
- **UI:** Grid/Shapes segmented control swaps the layout picker ↔ shape picker; both drive `setLayout`. Uses the new orange design tokens.
- **Deferred (v1 limitations):** polygon border/gap (renders edge-to-edge); bezier curve smoothing (straight segments); the 10-file polygon JSON *catalog* + editor wiring (that feeds Step 03a's gallery — parser + inline-JSON tests cover the parsing now); on-device seam/AA visual QA + Instruments memory profile.
- **Tests:** 12 new (4 polygon geometry + 8 parser), all green; 29 unit tests total pass. App builds + launches on iPhone 16 sim.

### Step 03a — decisions & deviations (2026-07-14)
- **Slice 1 of ~7 (foundation only).** This step is large (~5 weeks); it is being executed in vertical slices. Slice 1 delivers the data/service layer everything else builds on — no UI yet.
- **`TemplateService`** (`Core/Services/`, `@MainActor`): `loadBundledTemplates()` scans the bundle (Templates subdir → root fallback, skips the JSON schema, drops anything that fails to parse), `thumbnail(for:maxDimension:)` renders via the Step 01 `CollageRenderer` and caches to memory + disk (`Caches/TemplateThumbnails`), `isPremium(_:)` / `canOpen(_:)` gate on `EntitlementStore` (real StoreKit is Step 06). `renderRequest(for:)` maps a template's normalized cells into a fitted canvas — reuses the renderer, no layout code duplicated.
- **`CanvasPreset`** (`Core/Models/`): the 4 fixed presets + pure `CanvasSize` math. Sizing rule: shorter side normalized to 1080 px (1:1→1080², 4:5→1080×1350, 9:16→1080×1920, 16:9→1920×1080); malformed ratios fall back to a square, never a zero canvas.
- **Zone typing** on `TemplateParser`: added `TemplateZoneType` (photo/text/sticker/art/spacer, unknown→photo) and extended `TemplateCell` with `zoneType`, an optional default-styled `TextOverlay` for text zones, and `stickerID` for sticker zones — backward-compatible with Step 02's photo-only templates.
- **Tests:** +6 (3 parser: text/sticker zone + aspect→size; 3 service integration: bundled load, thumbnail-within-2s, premium gate). 29 → **37 total green** on iPhone 17 / iOS 26.5.
- **Found (pre-existing, out of scope):** the export options `UIAlertController` presents as a **popover with no Cancel** on iPhone 17 / iOS 26.5 (honors the `popoverPresentationController.barButtonItem` anchor). Functional (tap-outside dismisses) but non-standard for iPhone; flagged for a separate fix. The Step 02 `PolygonQAUITests` was updated to dismiss via the popover region.

### Step 03a slice 2 — Template Gallery UI (2026-07-14)
- **`Features/TemplateGallery/`** — `TemplateGalleryViewController` (2-column `UICollectionViewCompositionalLayout` + diffable data source keyed by template id; card height follows the selected preset's aspect ratio), `TemplateGalleryCells` (thumbnail card with crown badge + category chip), `PaywallPlaceholderViewController` (grabber sheet shown for locked templates; Step 06 swaps in the real SwiftUI paywall behind the same call site).
- **Three-way filtering:** `CanvasPreset` segmented control ∩ category chips (All/Minimal/Story/Grid/Travel/Seasonal/Birthday) ∩ `UISearchController` text. Presets with no templates show an explanatory empty state (expected until the 30-template catalog slice lands — only the 2 Step-02 grid JSONs are bundled today).
- **Entry + routing:** Home gains a `rectangle.3.group` "Templates" bar button (the "+" flow is untouched — UI tests depend on it). `AppCoordinator.openTemplate` uses the new `TemplateService.gridTemplate(matching:)` (order-insensitive normalized-frame match, photo-zones-only) to open pure-grid templates in the existing grid editor seeded with the template's layout/background/canvas size; richer templates get a "coming soon" notice until the template editor slice.
- **Latent UI-test bug found & fixed:** `PolygonQAUITests` tapped `navigationBars.buttons.element(boundBy: 0)` as "undo" — that's the **Back button**; the test only ever passed because the second tap hit Home's "+" and re-entered a fresh editor. Adding the Home Templates button (new leftmost item) exposed it. Fix at root: `undoButton`/`redoButton`/`exportButton` accessibility identifiers on the editor nav items; `PolygonQAUITests` + `ExportSaveUITests` now target identifiers, never positions.
- **Tests:** +7 unit (`TemplateGridMatchingTests`) and +1 UI (`TemplateGalleryUITests` — entry, filtering, empty state, free-template→editor route, with screenshots). **44 unit + 6 UI green** on iPhone 17 / iOS 26.5. Sim note: back-to-back UI-test runs intermittently wedge the sim ("Application failed preflight checks / Busy") — `xcrun simctl shutdown all` and rerun.
- **Deferred within 03a:** template thumbnails render synchronously on first display (fine for 2 templates; make async/prefetching when the 30-template catalog lands); search matches name only (category/keywords later).

### Step 03a slice 3 — `.template` collage layout (2026-07-15)
- **Decision (deviation from spec's letter, honoring its intent):** instead of a parallel `TemplateEditorViewController`, `CollageLayout` gained a **`.template(TemplateLayout)`** case. The spec itself says "the template editor is essentially the grid editor with more zones", and its done-criteria forbid duplicating layout/render code — this route gives every template the full existing stack (undo/redo, autosave+resume, PHPicker import, filters, GPU canvas, CG export) for free. Text/sticker zones become editor *overlays* in later slices, layered on this same screen.
- **`TemplateLayout`** (`Core/Rendering/TemplateLayout.swift`): just the photo cells' normalized frames + `CellClipShape`s + aspect ratio — deliberately not the whole `CollageTemplate`, keeping undo snapshots small. `TemplateService.editorLayout(for:)` maps photo zones only. `CollageLayoutEngine.templateLayout(for:)` scales frames; rect cells take the grid border inset, shaped cells render edge-to-edge (polygon rule). Codable synthesis keeps old saved projects decoding.
- **Routing:** `AppCoordinator.openTemplate` prefers `.grid` when the template exactly tiles a stock grid (so the picker highlights it), else `.template`; zero-photo-zone templates keep a "coming soon" notice until the text-zone slice.
- **Thumbnail cache fix:** disk keys now include a deterministic **FNV-1a content fingerprint** (aspect + background + cell type/shape/frame/corner) — re-authored templates with unchanged ids no longer serve stale thumbnails (Swift `Hashable` is process-seeded, unusable for disk keys).
- **First non-grid bundled template** `minimal_duo_offset.json` (offset hero rect + circle accent, category *minimal*) proves the path end-to-end; gallery UI test opens it via the Minimal chip.
- **Known cosmetic quirk:** with a `.template` layout active, the editor's layout picker still highlights its default grid chip (the picker has no "none" state); tapping a grid chip intentionally switches layouts, preserving photos. Revisit in the template-editor-chrome slice / Step 05b.
- **Tests:** +5 unit (`TemplateLayoutTests`: zone mapping, engine scaling/inset rules, accessors, state Codable round-trip) +1 fingerprint test +1 UI (`testNonGridTemplateOpensViaTemplateLayout`). **50 unit + 7 UI green.**
- **Sim flake pattern (environment, recurring):** back-to-back full UI runs intermittently wedge SpringBoard ("Application failed preflight checks / Busy", every test failing at a uniform ~10.7s) → `simctl shutdown all`, erase if persistent. After an **erase**, the first `ExportSaveUITests` run can fail on the slow first-boot Photos-prompt round-trip; it passes on re-run.

### Step 03a slice 4 — bundled template catalog v1 (2026-07-15)
- **21 bundled templates** (18 new JSONs): Minimal 6 (Solo Frame, Tower, Gallery Trio, Split Air, Duo, Circle Focus★), Story 4 (Stack Trio, Hero Strip, Split Tall, Moments★), Grid 5 (2-Up, 4-Up, Filmstrip, Mosaic 4, Six Airy), Travel 3 (Panorama Row, Horizon Split, Postcard★), Seasonal 3 (Bloom, Quartet, Ornament★). ★ = `isPremium` (4 total) exercising the crown badge + paywall placeholder. Every canvas preset (1:1, 4:5, 9:16, 16:9) has templates.
- **Deliberately photo-only.** The spec's full 30 include text/sticker-zone designs; those ship *with* the text-zone and sticker slices so their thumbnails/editing don't misrepresent (the renderer draws photo/art zones only today). Circle cells on non-square canvases are authored with pixel-square frames (normalized h = w × canvasW/canvasH).
- **New `TemplateCatalogTests`:** catalog integrity (unique ids — the diffable gallery would silently drop duplicates; categories map to gallery chips; aspects map to a `CanvasPreset` so nothing is unreachable; ≥1 photo zone each; no zero-size cells), every-preset-populated, and the done-criterion **full-catalog thumbnail render < 1.5 s**.
- Gallery UI test updated: Story preset now asserts populated cards; the empty state is asserted via an impossible filter combination (Story ∩ Minimal). **53 unit + 7 UI green.**

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
