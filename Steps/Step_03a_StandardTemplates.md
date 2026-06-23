# Step 03a — Standard Template & Frame Editor
**Part:** 1 — Development
**Weeks:** 13–17
**Depends on:** Step 02 complete
**Unlocks:** Step 03b

---

## Goal

Build the template gallery and frame editor — the SCRL-style experience where users pick a pre-designed layout, drop their photos into it, customize text and stickers, and export. This is the highest-engagement feature for social media users.

---

## Technical Specs

### Template System Architecture

```
TemplateService
├── loadBundledTemplates()     → reads JSON from Resources/Templates/
├── loadPremiumTemplates()     → downloads from CDN (premium users only)
├── cachedTemplates            → stored in SwiftData (offline access)
└── thumbnail(for:)            → returns cached CGImage thumbnail
```

Templates are rendered at full quality using the same `CollageRenderer` from Step 01. The template editor is essentially the grid editor with more zones (text, stickers, background art) in addition to photo cells.

### Zone Types in Templates

| Zone type | JSON `"type"` | User interaction |
|-----------|--------------|-----------------|
| Photo | `"photo"` | Tap → photo picker; pinch/drag within zone |
| Text | `"text"` | Tap → text input panel; style controls |
| Sticker | `"sticker"` | Tap → sticker picker sheet |
| Background art | `"art"` | Not interactive — decorative element from template |
| Spacer | `"spacer"` | Empty padding zone |

### Canvas Sizes
The user selects the canvas size before picking a template. Filter templates by compatible aspect ratio.

| Preset | Dimensions | Use case |
|--------|-----------|---------|
| Instagram Post 1:1 | 1080×1080 | Square feed post |
| Instagram Portrait 4:5 | 1080×1350 | Portrait feed post |
| Instagram Story / TikTok 9:16 | 1080×1920 | Stories, Reels |
| Landscape 16:9 | 1920×1080 | YouTube, Twitter/X |
| Freeform | User-defined | Custom dimensions |

---

## Checklist

### Template Service
- [ ] Create `Core/Services/TemplateService.swift`
- [ ] `loadBundledTemplates()` — parse all JSON files in `Resources/Templates/` at app launch
- [ ] Store parsed templates in memory; persist to SwiftData for offline access
- [ ] `thumbnail(for template: Template) -> CGImage` — generate at 300×300 using `CollageRenderer`; cache to disk
- [ ] `isPremium(template:) -> Bool` — check subscription status via `PurchaseService`

### Template Gallery UI (UIKit)
- [ ] Create `Features/TemplateGallery/TemplateGalleryViewController.swift`
- [ ] Use `UICollectionView` with `UICollectionViewCompositionalLayout` and a `UICollectionViewDiffableDataSource` for the 2-column grid (fast, prefetching-friendly with hundreds of templates)
- [ ] Top: canvas size selector (`UISegmentedControl`)
- [ ] Category tabs: horizontal `UICollectionView` of chip cells — All, Minimal, Story, Grid, Travel, Seasonal, Birthday
- [ ] Template cells show: thumbnail image, name, premium crown badge on locked templates
- [ ] Tap template → push `TemplateEditorViewController`
- [ ] Tap locked template → present `PaywallViewController` (SwiftUI via `UIHostingController` — paywall lives in SwiftUI)
- [ ] Search via `UISearchController` embedded in the navigation item

### Template Editor UI (UIKit + SwiftUI panels)
- [ ] Create `Features/TemplateEditor/TemplateEditorViewController.swift`
- [ ] Top toolbar: **Back** (confirm discard if unsaved), **Undo**, **Redo**, **Export**
- [ ] Center canvas: same UIKit `CanvasView` (CAMetalLayer) reused from Step 01
- [ ] Empty photo zones show a `+` icon tap target rendered in the canvas
- [ ] Bottom toolbar: a `UISegmentedControl` switches between panels. Each panel is a small SwiftUI view hosted via `UIHostingController`:
  - **Photos** panel (UIKit — opens `PHPickerViewController`)
  - **Text** panel (SwiftUI — `Form`-like styling controls)
  - **Stickers** panel (UIKit `UICollectionView` — performance matters)
  - **Background** panel (SwiftUI — small form)
  - **Adjust** panel (SwiftUI — three sliders)

### Text Zone Editor
- [ ] Tap a text zone in the canvas (UIKit hit-test) → present text input + SwiftUI styling panel as a bottom sheet via `UISheetPresentationController`
- [ ] Styling controls (SwiftUI inside the sheet):
  - Font picker — UIKit `UICollectionView` embedded via `UIHostingController` (font lists are long; we want prefetching)
  - Font size slider, letter spacing, line height, opacity — SwiftUI `Slider`
  - Color picker (preset swatches + custom color) — SwiftUI
  - Alignment, bold/italic/underline — SwiftUI
- [ ] Text is rendered onto the Metal canvas in real time (use `Core Text` via `CGContext`)
- [ ] `TextOverlay` model stores all styling properties + the text string

### Sticker System (UIKit)
- [ ] Create `Resources/Stickers/` folder with at least 3 bundled packs (20 stickers each):
  - `pack_basic.json` — everyday icons
  - `pack_nature.json` — leaves, sun, moon, weather
  - `pack_celebration.json` — stars, confetti, hearts
- [ ] Each sticker is a PNG at 256×256, included in the app bundle
- [ ] `Features/TemplateEditor/StickerPickerViewController.swift` — `UICollectionView` with pack-tab `UISegmentedControl`
- [ ] Tap sticker → adds it to the canvas as a freely positionable overlay (UIKit-level hit-testing)
- [ ] Sticker gestures: `UIPanGestureRecognizer` (move), `UIPinchGestureRecognizer` (resize), `UIRotationGestureRecognizer` (rotate), `UITapGestureRecognizer.numberOfTapsRequired = 2` (delete) — all composed with `simultaneousRecognition`

### Freeform Canvas
- [ ] "Freeform" canvas size option allows user to set custom width × height (min 100px, max 4000px)
- [ ] Snap guides appear when dragging elements: center X, center Y, canvas thirds
- [ ] Zoom control: pinch the canvas itself to zoom in for detail editing

### 30 Bundled Templates (create these JSON files)
Distribute across categories:
- [ ] 8 Minimal (clean, lots of whitespace, mono fonts)
- [ ] 6 Story (9:16, bold typography, portrait-oriented)
- [ ] 6 Grid (photo-heavy, small borders)
- [ ] 5 Travel (earthy tones, map/pin accents)
- [ ] 5 Seasonal (can be holiday/Christmas/summer — keep generic enough to reuse)

---

## Unit Tests

**Extend `TemplateParserTests.swift`:**
- [ ] `testTextZoneParsesCorrectly()` — `"type": "text"` maps to text zone with correct default styling
- [ ] `testStickerZoneParsesCorrectly()` — `"type": "sticker"` maps to sticker zone
- [ ] `testCanvasAspectRatioMapsToSize()` — `"1:1"` → `CGSize(1080, 1080)`, `"9:16"` → `CGSize(1080, 1920)`

**New: `ClaudeCollageTests/Integration/TemplateServiceTests.swift`:**
- [ ] `testBundledTemplatesLoadOnInit()` — `TemplateService` returns non-empty array at launch
- [ ] `testThumbnailGenerationCompletesWithinTimeout()` — thumbnail rendered within 2 seconds
- [ ] `testPremiumTemplateBlockedForFreeUser()` — `isPremium` returns true; free user cannot open it

Run: `Cmd+U` → all pass.

---

## Done Criteria

- [ ] Template gallery loads all 30 bundled templates with correct thumbnails in < 1.5s
- [ ] Text zones fully editable with all styling controls working in real time
- [ ] Stickers can be added, moved, resized, rotated, and deleted
- [ ] Exported image matches exactly what is shown in the preview canvas
- [ ] Freeform canvas with snap guides works correctly
- [ ] Premium gate correctly blocks access to premium templates for free users
- [ ] All 6 integration/unit tests pass
- [ ] No layout engine or rendering code was duplicated — Step 01's `CollageRenderer` is reused
