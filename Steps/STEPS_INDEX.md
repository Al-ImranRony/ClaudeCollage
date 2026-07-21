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
| **03a** | `Step_03a_StandardTemplates.md` | Frame/story template editor | 13–17 | ✅ Complete (2026-07-17) — all 7 slices done: foundation, gallery, `.template` layout, catalog (33 templates), text-zone editor, sticker system, freeform + snap. All done-criteria met. **77 unit/integration + 7 UI tests green.** See Step 03a notes below |
| **03b** | `Step_03b_CarouselTemplates.md` | SCRL-style carousel mode | 18–22 | 🟢 Core complete — slices 1–8 done (…+ persistence/resume). All done-criteria met **except video-slideshow export, deferred to Step 04's VideoComposer** (the plan itself ties it there). 127 unit+int + 18 UI green. See Step 03b notes below |
| **04** | `Step_04_VideoCollage.md` | Video collage + universal export | 23–30 | 🟡 In progress — slice 1 done (export engine foundation: `ExportPreset` + `ImageExporter` + `VideoComposer` direct-AVAssetWriter; 6 spec integration tests + 9 preset tests green). See Step 04 notes below |
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

### Step 03a slice 5 — text-zone editor (2026-07-16)
- **Text zones are editable overlays on the existing grid/template editor** (the slice-3 decision), not a separate editor. `GridEditorState` gained `textOverlays: [TextOverlay]` — part of the value snapshot, so text edits ride the existing undo/redo + debounced autosave with zero new machinery. Backward-compatible decode (`decodeIfPresent ?? []`) keeps Step 01–04 project blobs loading; `TextOverlay` got a defensive Codable + `isBold`/`isItalic`/`isUnderlined`.
- **One renderer for preview AND export** (`Core/Rendering/TextRendering.swift`): builds the `NSAttributedString` (font w/ bold-italic symbolic traits, kern, alignment, line-height, colour×opacity, underline) and draws it vertically-centred + clipped. The live canvas (`TextOverlayView`, a GPU-composited `UILabel` per overlay layered above the cells — no CPU recomposition, per the perf rule) and `CollageRenderer` (Core Graphics, `RenderRequest.textOverlays`) both go through it, so what you see is what exports. Frames are normalized (0…1); `fontSize`/`letterSpacing` are **reference-canvas points** (short side 1080) scaled per target via `fontScale = targetCanvas.h / referenceCanvas.h`.
- **Editing:** tapping a text zone (hit-tested above cells via `CanvasView.overlayID(at:)`) opens a `UISheetPresentationController` bottom sheet hosting a SwiftUI `TextStyleSheet` (text field, font-chip picker, alignment, bold/italic/underline, swatches + custom `ColorPicker`, size/letter-spacing/line-height/opacity sliders — all on Theme tokens). Live edits stream via `previewTextOverlay` (overlay-only refresh, no cell rebuild, no undo spam); dismiss commits one snapshot.
- **Thumbnails now render text** (`TemplateService.renderRequest` includes overlays + `textFontScale`; the disk-cache fingerprint now folds in text content/style so an edited caption busts a stale thumb). `AppCoordinator.openTemplate` seeds `textOverlays` from `template.cells.compactMap(\.textStyle)`.
- **+7 bundled text templates** (photo **and** text): Story ×2 (Quote Block, Caption Hero), Travel ×2 (Postcard Note, Passport★), Seasonal ×2 (Season's Greeting, Give Thanks), Birthday ×1 (Birthday Bash) — **catalog 21 → 28**, and the first Birthday-category template. Text zones use bold PostScript faces (the parser reads `text`/`fontName`/`fontSize`/`color`/`alignment`); schema documents the text fields.
- **Deviation from the kickoff plan:** every text template keeps ≥1 photo zone, so all route through the `.grid`/`.template` path and the catalog's "≥1 photo zone" invariant holds. Truly text-only (zero-photo) templates — which would need a cell-less canvas — are deferred; the `openTemplate` "coming soon" notice stays as the fallback for them. Sticker/font-weight JSON fields and an "add arbitrary text" affordance belong to later slices (sticker system / freeform).
- **Tests:** +10 (`TextOverlayRenderingTests` ×9: state round-trip + legacy-empty decode, overlay defensive decode, normalized-frame math, font-scale, bold/italic traits, missing-font fallback, hex round-trip, **renderer-draws-text**; +1 `TemplateServiceTests` text-template seeding/routing/thumbnail). **63 unit + 7 UI green** on iPhone 17 / iOS 26.5.
- **Recommended owner QA (on device):** open a text template (e.g. Birthday Bash / Quote Block), edit a caption + restyle it, confirm the canvas matches the exported image, and resume the project from Home to confirm overlays persist.

### Step 03a slice 6 — sticker system (2026-07-17)
- **Stickers are editable overlays on the same editor** (mirroring slice-5 text), carried in `GridEditorState.stickerOverlays` so add/move/resize/rotate/delete ride the existing undo/redo + debounced autosave. Backward-compatible decode (`decodeIfPresent ?? []`) keeps pre-sticker blobs loading; `StickerOverlay` is defensively Codable (normalized centre + square `sizeNorm` as a fraction of canvas *width* + rotation + tint + opacity).
- **One renderer for preview AND export** (`Core/Rendering/StickerRendering.swift`): resolves a sticker to a tinted SF Symbol and draws it aspect-fit + rotated. The live canvas (`StickerOverlayView`, a GPU-composited `UIImageView`, layered above text) and `CollageRenderer` (`RenderRequest.stickerOverlays`, drawn above text) both go through it → preview == export.
- **Deviation (documented):** stickers are **SF-Symbol-backed**, not the plan's 256×256 PNGs — vector symbols stay crisp at any canvas scale and avoid shipping 60 binary blobs; the plan's **pack-manifest architecture is preserved** (`Resources/Stickers/pack_basic|nature|celebration.json`, 20 each = 60). `StickerCatalog` loads packs + resolves ids; a missing symbol falls back to a filled star so a sticker never renders blank.
- **Interaction:** each sticker view owns pan + pinch + rotate (simultaneous recognition) + double-tap-delete + tap-to-select (dashed selection chrome). Cell gestures stay **inert on sticker points** (the VC's `cellIndex(at:)` returns nil there) so the two never fight. `StickerPickerViewController` (`Features/TemplateEditor/`, `UICollectionView` + pack-tab segmented control) presents as a sheet.
- **Editor chrome:** rather than retrofit the plan's full 5-panel segmented bar onto the slice-3 controls-scroll editor (which would risk the passing UI tests), a compact **add-bar** (Text / Sticker) sits between canvas and controls. "Add Text" also delivers the **arbitrary-text affordance deferred from slice 5**. Templates seed sticker zones into overlays (`TemplateService.stickerOverlays(for:)` in `openTemplate` + gallery thumbnails; fingerprint folds in `stickerID`).
- **+5 sticker-bearing templates** → catalog **28 → 33** (meets the 30-template done-criterion): Birthday (Confetti Party), Seasonal (Winter Sparkle), Grid (Party Grid), Minimal ×2 (Accent Mark, Framed Quote). Distribution now Minimal 8 / Story 6 / Grid 6 / Travel 5 / Seasonal 6 / Birthday 2.
- **Tests:** +9 `StickerOverlayRenderingTests` (state round-trip + legacy-empty decode, defensive decode, normalized-frame math, symbol-resolves-and-falls-back, **renderer-draws-sticker**, catalog 3×20 unique ids, template sticker seeding, VM add/remove undo). Catalog count assertion bumped 21 → 30. **72 unit/integration green.**

### Step 03a slice 7 — freeform canvas + snap guides + zoom (2026-07-17)
- **Freeform:** a Home "Custom Size" bar button (`aspectratio`) prompts for W×H (clamped 100–4000) and starts a blank **one-cell `.template`** collage at that ratio (`AppCoordinator.startFreeformProject`), inheriting the whole editor stack (photos/text/stickers/export) at any size. The existing "+" grid flow is untouched (UI tests depend on it).
- **Snap guides** (`Core/Rendering/SnapEngine.swift`, pure + unit-tested): a dragged sticker's centre snaps per-axis, independently, to the canvas centre + rule-of-thirds within a normalized threshold, with a light tick when a guide grabs. The canvas draws the engaged lines via a `CAShapeLayer` (`zPosition` above cells/text/stickers).
- **Canvas pinch-to-zoom** (1–3×, view-only — never part of state/export) for detail editing, scaling `contentContainer`'s transform; **gated via a `UIGestureRecognizerDelegate`** so the zoom pinch only accepts empty-background touches and never fights the cell/sticker pinch. Settles back to 1× on release. Frame math runs at identity transform then re-applies zoom, so layout stays correct.
- **v1 limitations (documented):** snapping applies to stickers (the draggable elements — text is tap-to-edit); panning a zoomed canvas and snapping to another element's edges are future enhancements.
- **Tests:** +5 `SnapEngineTests` (centre snap, thirds, no-snap-when-far, independent axes, threshold boundary). **77 unit/integration + 7 UI tests green** on iPhone 17 / iOS 26.5.
- **Step 03a done-criteria — all met:** 30+ templates load with thumbnails < 1.5 s; text zones fully editable in real time; stickers add/move/resize/rotate/delete; preview == export (shared Text/Sticker rendering, unit-proven); freeform + snap guides work; premium gate blocks free users; the specified 6 parser/service tests pass (plus many more); no layout/render code duplicated (everything is overlays on the Step 01 stack).
- **Recommended owner QA (on device):** add a sticker + drag it (confirm snap guides + haptic), pinch-zoom for detail, export and confirm the image matches the canvas (photos + text + stickers), start a Custom-Size collage and confirm it opens at the chosen ratio, and resume from Home to confirm stickers persist.

### Step 03b slice 1 — carousel foundation (2026-07-18)
- **Executed in vertical slices, like 03a.** Slice 1 is the pure data/service layer only — no UI, no bundled templates yet.
- **`CarouselFrame`** (`Core/Models/`): a value type whose content is **one `GridEditorState` per frame** — the same snapshot the grid/template editor and `CollageRenderer` already drive. This is the **same zero-duplication decision as 03a slice 3** (`.template` reused the grid stack): a carousel frame gets undo/redo, autosave, PHPicker import, filters, the GPU canvas, and CG export for free. The plan's `backgroundOverride` is just `state.background`. Defensive Codable.
- **`PanoramicStitcher`** (`Core/Rendering/`): `split` cuts a wide image into N equal slices via `CGImage.cropping` (shares pixels, no resample); `stitch` composites edge-to-edge into a fresh bitmap; `verifyEdgeAlignment` asserts the clean-split invariant (all frames identically sized → 0px gap/overlap). Split↔stitch round-trips **pixel-for-pixel** (unit-proven). **Deviation/assumption:** Core Graphics cropping, not vImage (exactness comes from copy-free crops, not SIMD); source's split-axis length is assumed divisible by N (import pre-crops), else up to N-1 trailing px are dropped.
- **`CarouselService`** (`Core/Services/`): pure `[CarouselFrame]`→`[CarouselFrame]` transforms — `reorder`, `addFrame` (caps at 10, new frame inherits the last frame's layout/bg/border but no photos), `deleteFrame`, all re-indexing to a contiguous 0-based run; `syncEdit` broadcasts one `StyleChange` (`.backgroundColor`/`.font`/`.textColor`/`.borderWidth`) across every frame (matched-carousel sync edit).
- **Reused Step 00 scaffold:** `CollageMode.carousel`, the `CarouselType` enum (panoramic/matched/scrollThrough/gridPreview), `CollageProject.{carouselType,frameCount}`, and `Resources/CarouselTemplates/carousel_schema.json` already existed.
- **Tests:** +8 `CarouselStitcherTests` (TDD — watched RED first): split count, equal widths, edge alignment, stitch round-trip, reorder/syncEdit/addFrame/deleteFrame. **85 unit+integration + 9 UI green** on iPhone 17 / iOS 26.5.
- **Deferred to later 03b slices:** pixel/render-coupled builders (`buildPanoramicCarousel`, `buildGridPreviewCarousel`), the carousel template parser + ~20 bundled JSON templates + their 2 integration tests, the CarouselEditor VC + frame navigator (reorder/add/delete strip) + sync-edit toggle, SwiftUI type selector, panoramic source picker, `UIPageViewController` preview player, safe-zone overlay, and carousel export (ZIP-of-frames + video slideshow).

### Step 03b slice 2 — carousel parser + 20 bundled templates (2026-07-18)
- **`CarouselTemplateParser`** (`Core/Services/`): typed + defensive, mirroring `TemplateParser` exactly — `canvasAspectRatio` is the one hard requirement; unknown/absent `carouselType`→`.matched`, absent `frameCount`→`frames.count`, `splitAxis`→`.horizontal`. Each frame's zones reuse the standard public `TemplateCell` (the carousel schema $refs the template cell def), and background reuses `TemplateBackground` (changed `private`→internal), so a carousel frame maps straight onto a `GridEditorState` downstream. Model types: `CarouselTemplate`, `CarouselTemplateFrame`, `PanoramicSource`.
- **`TemplateService.loadBundledCarouselTemplates()` + `carouselTemplates`**: loads the carousel catalog, sorted premium-last then by name, kept separate from the standard `templates` gallery.
- **⚠️ Resource-flattening gotcha (important for future bundled-asset work):** the app bundles `ClaudeCollage/Resources` such that subfolders are **flattened into the bundle root** — there is NO `Templates/` or `CarouselTemplates/` subdirectory in the built `.app`. `bundle.urls(forResourcesWithExtension:subdirectory:"Templates")` returns empty; the standard loader only worked via its **root fallback**. Since carousel JSONs also carry a top-level `canvasAspectRatio`, the standard `CollageTemplate` parser would happily decode them into **empty (cell-less) gallery templates**. Fix: both catalogs are separated by the **`carousel` filename prefix** (the plan's own naming) — the standard loader now skips `carousel_*` files, the carousel loader selects only them (subdir query kept as a forward-compat fallback if bundling ever preserves folders).
- **20 bundled carousel templates** (`Resources/CarouselTemplates/carousel_*.json`): 5 panoramic, 6 matched, 5 scroll-through, 4 grid-preview; 4 premium (city, quotes, story-travel, gridpreview-6cell); every `CarouselType` + all 4 presets represented; frameCounts 2–10. Cells are simple full-bleed photo / photo+caption / grid layouts (renderable once the editor/builder slices land).
- **Tests:** +4 `CarouselTemplateParserTests` (frameCount/type/panoramicSource, typed cells incl. text zone, graceful defaults, malformed throws) +2 `TemplateServiceTests` (≥15 load & no gallery-ID overlap & frames==frameCount; all 4 types present). TDD (watched RED). `TemplateCatalogTests` still green → carousel files no longer pollute the standard catalog. **91 unit+integration + 9 UI green.**
- **Env note (recurring, worse today):** the sim wedged on "Application failed preflight checks / Busy" for **three** consecutive launches after `xcodegen generate`; `shutdown all` alone didn't clear it. What worked: `simctl shutdown all && simctl erase all`, then **explicitly `simctl boot <id>` + `simctl bootstatus -b`** (wait for terminal boot) BEFORE `xcodebuild test`. First launch after erase logs benign CoreData "Application Support missing → recovery successful" noise.

### Step 03b slice 3 — carousel builders (2026-07-18)
- The pure logic that turns a source into `[CarouselFrame]` — the last piece before the editor UI. All builders on `CarouselService`.
- **`CarouselBuild`** — `{ frames: [CarouselFrame], images: [UUID: CGImage] }`. The `images` map (imageID → pixels) is what the editor seeds into its photo cache. Plain struct, not `Sendable` (CGImage isn't) — a build stays actor-local.
- **`buildPanoramicCarousel(from:frameCount:axis:aspectRatio:background:)`** — splits a wide image via `PanoramicStitcher`, binds each slice to a full-bleed one-cell frame with a fresh `imageID`, returns the slices to seed. Returns `CarouselBuild`.
- **`buildCarousel(from: CarouselTemplate)`** (`@MainActor` — sticker lookup reads `StickerCatalog`) — maps each template frame's zones onto a `GridEditorState`: photo zones → editor cells, text → `textOverlays`, sticker → `stickerOverlays`. **Reuses the exact `TemplateService` mapping the single-template `openTemplate` path uses** — added cells-based overloads `editorLayout(templateID:name:aspectRatio:cells:)` and `stickerOverlays(for cells:)`; the `CollageTemplate` versions now delegate to them (no duplicated geometry/seeding). Frames sorted by `index`, re-numbered contiguously.
- **`buildGridPreviewCarousel(from gridState:aspectRatio:)`** — frame 0 is the whole grid as authored; frames 1…N each zoom into one grid cell (full-bleed, carrying that cell's `imageID` + `transform` + `filters`), reusing the grid's image ids so no new pixels are produced. Returns `[CarouselFrame]`.
- **Tests:** +6 `CarouselBuilderTests` (TDD). **97 unit+integration + 9 UI green.**
- **Deferred to the UI slice:** a VM **seed-image-by-id** entry point (today `GridEditorViewModel.setImage` generates its own id; consuming `CarouselBuild.images` needs a `seedSourceImage(_:forID:)`), and all editor/navigator/type-selector/preview/export UI.

### Step 03b slice 4 — carousel editor VM + frame navigator UI (2026-07-18)
- **Slice 4a — `CarouselEditorViewModel`** (`Features/CarouselEditor/`, `@MainActor`): owns the frame list + selection + a shared `[UUID: CGImage]` cache; structural ops with **carousel-level undo** (`UndoStack<[CarouselFrame]>`) — `addFrame` (selects it, caps 10), `deleteFrame` (keeps ≥1, clamps selection), `moveFrame` (selection follows the moved frame), `applySyncEdit` (broadcasts a `StyleChange` to all frames). Per-frame *content* undo stays in the embedded grid editor. Matched carousels default sync-edit on. +12 `CarouselEditorViewModelTests`.
- **Reuse primitive:** frame editing rides `GridEditorViewModel.restore(state:images:)` + `sourceImageSnapshot()` (both already existed) — `currentEditorState()` seeds the editor, `commitCurrentFrame(state:images:)` pulls it back. Zero editor duplication.
- **Slice 4b — `CarouselEditorViewController` + `CarouselFrameCell`:** the carousel screen is a **frame-navigator overview** (2-col grid of frame cards, thumbnails rendered via a throwaway VM + the grid renderer). Tapping a frame **pushes the existing `GridEditorViewController`** (seeded via restore); on return the state commits back. Nav-bar undo/redo (frame structure) + export; bottom toolbar = sync-edit toggle + add-frame + preview; delete + reorder (Move Left/Right) in each card's context menu. Home gains a **`carouselButton`** (`rectangle.stack`); `AppCoordinator.startCarousel` seeds a 3-frame matched 4:5 carousel and wires frame editing through `pushEditor`. +3 `CarouselEditorUITests`.
- **Why navigator+push, not embedded canvas:** embedding `GridEditorViewController` as a child would fight over the nav bar + the slice-03a back-swipe-guard's pop-recognizer takeover. Pushing it instead reuses the editor **unmodified** and is verifiable headless. Documented as the v1 shape.
- **v1 deviations (documented in-file):** single-screen live-canvas+strip → navigator+push-to-edit; reorder via context menu (not long-press drag); sync-edit broadcasts background+border on return (live font sync later); **carousel is in-memory (no resume/persistence yet)**; preview + export show a coming-soon notice. Also: the frame cards were first a full-height horizontal strip (only 1 card visible → XCUITest couldn't count off-screen cells); switched to a 2-col vertical grid so all frames show + count reliably.
- **109 unit+integration + 12 UI green.** (ExportSave passes on a Photos-auth-determined sim; it flaked once here purely because this session ran `erase all` — the documented Photos-prompt flake, unrelated to code.)

### Step 03b slice 5 — type selector + panoramic source picker (2026-07-18)
- **`CarouselStartConfig`** (value on `CarouselService.swift`): `type` + `frameCount` (clamped 2…10 on init) + `splitAxis` + `aspectRatio`, with per-type option visibility (`showsSplitAxis` = panoramic only; `showsFrameCount` = false for grid preview, which derives its count from the grid). **`CarouselService.blankCarousel(type:frameCount:aspectRatio:)`** builds fresh editable frames — full-bleed photo cell per frame for matched, photo + bottom caption zone for scroll-through.
- **`CarouselTypeSelectorView`** (SwiftUI, `Features/CarouselEditor/`): four selectable type cards (symbol + title + subtitle), a frame-count `Stepper`, a split-axis segmented picker (panoramic only), an aspect picker, and a Create button (labelled "Choose Photo" for panoramic). Presented from Home via `UIHostingController`. Accessibility ids `carouselType-<rawValue>` + `carouselCreateButton`.
- **`PanoramicSourcePicker`** (NSObject `PHPickerViewControllerDelegate` — the coordinator isn't a responder): single-image PHPicker that loads + downsamples the wide source off-main, **mirroring the grid editor's import to dodge the Swift 6 @MainActor/PhotoKit trap** ([[swift6-dispatchworkitem-mainactor-trap]]) — the @Sendable load closure captures only `[weak self]` + Sendable locals; `completion` is touched only after hopping to main. Capped at 3200px so slices stay crisp.
- **`AppCoordinator.startCarousel`** now presents the selector and routes each type through its slice-3 builder: matched/scroll-through → `blankCarousel`; grid preview → `buildGridPreviewCarousel` (default 4-up grid → 5 frames); panoramic → source picker → `buildPanoramicCarousel`. Replaces slice 4's hardcoded 3-frame seed.
- **Tests:** +6 `CarouselStartTests` (config clamp/visibility, blank builders) +2 `CarouselTypeSelectorUITests` (matched → 3 frames; **grid preview → 5 frames, exercising the builder path end-to-end through the UI**). Existing carousel UI tests updated to enter through the selector. **115 unit+integration + 14 UI green.**
- **v1:** grid preview seeds a default 4-up grid (choosing an existing grid project as the source is a follow-up); panoramic photo-pick is **manual QA** (system PHPicker isn't driven headlessly).

### Step 03b slice 6 — preview player + safe-zone overlay (2026-07-18)
- **`SafeZonePreset`** (`Core/Models/SafeZone.swift`): `off` / `instagramStory` / `instagramReels` / `tiktok` / `generic`, each returning the normalized (0…1) rects the platform UI covers (`coveredRegions`). Pure geometry, **preview-only — never exported**. +5 `SafeZoneTests`.
- **`SafeZoneOverlayView`** — draws the dimmed bands over a frame image (fills the image's rect so normalized regions map straight to pixels).
- **`CarouselPreviewViewController`** — full-screen swipe-through preview on a **`UIPageViewController` (.scroll)** for native paging physics; one rendered frame per page + optional safe-zone overlay (aspect-fit container so overlay aligns to the image). Chrome = close / `n / N` counter / safe-zone `UIMenu` / export / `UIPageControl` dots, toggled on tap (a `UIGestureRecognizerDelegate` gate ignores taps on `UIControl`s). Export shows a coming-soon notice (real export is slice 7). Presented from the editor's Preview button, which renders each frame once via a throwaway VM + the grid renderer.
- **Tests:** +5 unit +2 `CarouselPreviewUITests` (opens showing "1 / 3" + safe-zone control; closes back to the editor). **120 unit+integration + 16 UI green.**

### Step 03b slice 7 — image-set (ZIP) export (2026-07-18)
- **`CarouselExporter`** (`Core/Services/`): `writeFrames` writes each frame as a zero-padded `frame_NN.jpg`; `exportImageSet` renders them under `<baseName>/` and archives that folder to `<baseName>.zip`. **The zip is made with `NSFileCoordinator.coordinate(readingItemAt:options:[.forUploading])`** — the platform's own directory→zip (it hands back a temp `.zip` of the coordinated folder), so **no third-party zip dependency**. +3 `CarouselExporterTests` (numbered JPEGs, non-empty zip, empty→throws).
- **Editor Export button → action sheet:** "Export as Images (ZIP)" renders every frame **full-resolution** (throwaway VM + `renderExport`), zips them, and offers the archive via `UIActivityViewController` (Files / AirDrop — Camera Roll can't hold a numbered folder). "Export as Video" = coming-soon notice (**video slideshow lands with Step 04's `VideoComposer`**).
- **Preview player's export** now routes back to the editor's full-res export (`dismiss` → `onExport`) instead of a placeholder.
- **Tests:** +3 unit +1 `CarouselExportUITests` (offers both image + video options; the system share sheet isn't driven headlessly). **123 unit+integration + 17 UI green.**
- **Remaining in 03b:** video-slideshow export (deferred to Step 04), carousel **persistence/resume** (still in-memory), and the optional bundled-carousel-template gallery.

### Step 03b slice 8 — carousel persistence + resume (2026-07-18)
- **`CollageProject.carouselData`** (`Data?`): serialized `[CarouselFrame]` (each frame is a `GridEditorState`). Photos live on disk as JPEGs keyed by image id, shared across frames — same on-disk scheme as grid projects. Adding an optional property is a SwiftData lightweight-migration-safe change.
- **`ProjectStore`**: `saveCarousel` / `scheduleSaveCarousel` (0.4s debounce, mirrors grid) / `loadCarouselViewModel` + a frame-0 gallery thumbnail. The image write/load helpers were **generalized to an explicit `Set<UUID>`** of referenced ids (grid = its cells' ids; carousel = the union across all frames). `ProjectSummary` gained `mode` so the gallery can distinguish carousels.
- **`AppCoordinator`**: creating a carousel **saves it immediately** (so it lands on Home) and attaches debounced autosave; **`openProject` routes by record type** — `loadCarouselViewModel` first (returns nil for non-carousels → falls through to the grid editor). Frame edits commit back to the carousel VM on return from the grid editor, which triggers autosave.
- **Tests:** +4 `CarouselPersistenceTests` (frames/type/per-frame-state round-trip, tagged-carousel-in-summaries, photos-reload-from-disk, grid≠carousel) +1 `CarouselEditorUITests` resume flow (create → +frame → Home → reopen → **4 frames intact**). `GridEditorFlowUITests` still green (grid resume unaffected by the routing change). **127 unit+integration + 18 UI green.**
- **Step 03b done-criteria:** all four types create end-to-end; panoramic edge alignment unit-proven; navigator reorder/add/delete with undo; sync-edit; native swipe preview; **image-set ZIP export**; persistence/resume — all met. **Only video-slideshow export remains, and the plan ties it to Step 04's `VideoComposer`** (not yet built) → deferred there. Panoramic photo-pick is manual QA (system PHPicker).
- **Note:** `project.yml` was reformatted by a tool during this slice (DEVELOPMENT_TEAM quotes/comment stripped) — the signing value `G9AZVLUA7S` is preserved; benign.

### Step 04 — slice plan (2026-07-22)
Step 04 is large (~8 wks, two deliverables: Video Collage editor + Universal Export system). Executed in vertical slices like 03a/03b:
1. **Export engine foundation (no UI)** — `ExportPreset` + `ImageExporter` + `VideoComposer` (direct AVAssetWriter slideshow). ✅ done below.
2. `UniversalExportSheetView` (SwiftUI) wired into Grid/Template/Carousel editors (image + carousel-video paths); unblocks 03b's deferred carousel video export end-to-end.
3. Video cells — `AVURLAsset` load, `AVMutableComposition` assembly, per-cell affine-transform layout, trim/loop/mute/volume.
4. Transitions + text/sticker overlays baked via `AVVideoCompositionCoreAnimationTool`; mixed photo+video.
5. `VideoEditorViewController` + `VideoCanvasView` (AVPlayerLayer) + per-cell controls + background music mixing.
6. Save-to-Photos / Quick Share / progress + Cancel / Live Activity / beat-sync.

### Step 04 slice 1 — export engine foundation (2026-07-22)
- **`ExportPreset`** (`Core/Models/ExportPreset.swift`): pure value type backing Section 1 of the export sheet. `preset(for: ExportSettings.Platform)` returns the enforced aspect + target pixel size + media kind + default video/image format per the spec table: Story/TikTok/WhatsApp = 1080×1920 (9:16), YouTube = 1920×1080, **Twitter/X = 1280×720 (720p, intentionally lower)**, IG Post = 1080×1080, Print = 4:3 JPEG **image-only**, Custom = no enforced size/aspect (`nil`) + media `.both`. `matchesCanvas(aspectRatio:)` drives the "resize canvas?" mismatch warning (Custom matches anything). +9 `ExportPresetTests`.
- **`ImageExporter`** (`Core/Services/ImageExporter.swift`): encodes a composited `CGImage` → JPEG(quality)/PNG via `CGImageDestination`, at `.full`/`.half`/`.custom(size)` resolution. Pure; caller owns save/share. (Section 2 image path.)
- **`VideoComposer`** (`Core/Rendering/VideoComposer.swift`): the video export engine. `renderSlideshow(frames:size:secondsPerFrame:fps:codec:container:to:progress:)` writes a still-per-page slideshow **directly via `AVAssetWriter` + `AVAssetWriterInputPixelBufferAdaptor`** — NO `AVAssetExportSession` (avoids SCRL's resample-softening bug). 32BGRA pixel buffers, aspect-fill draw, H.264/MP4 default (HEVC/MOV premium later). Runs on a private `DispatchQueue`, bridged to async via a checked continuation; `finishWriting` awaited through a `DispatchSemaphore` (no non-Sendable capture). **This is the deferred 03b carousel video-export engine** — slice 2 wires it in. Because editors always hand it a fully-composited frame, "all overlays baked in" is structural.
- **Tests:** the spec's 6 `ExportServiceTests` (image dimensions / JPEG-quality→size / PNG lossless round-trip / MP4 produced+1 track / dims match preset / composited pixels survive to the file via `AVAssetReader` readback) + 9 `ExportPresetTests`. **143 unit+integration + 18 UI green** (+15 unit/int this slice; no existing production code touched — purely additive).
- **Deviations/notes:** slideshow appends each frame at 30fps for `secondsPerFrame` (guarantees the last frame a real duration); video *cells* (AVAsset trim/audio) and transitions are later slices. Print preset's "300 DPI equivalent" uses the app's 1080-short-side sizing rule (`CanvasSize`) for now.

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
