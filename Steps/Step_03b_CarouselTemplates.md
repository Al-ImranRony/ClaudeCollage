# Step 03b — Carousel Template Editor (SCRL-Style)
**Part:** 1 — Development
**Weeks:** 18–22
**Depends on:** Step 03a complete
**Unlocks:** Step 04

---

## Goal

Build the carousel editor as a distinct first-class mode — not a variant of the template editor. A carousel is a sequence of linked frames designed to be swiped through on Instagram, TikTok, or any social platform. This step implements all four carousel types, the frame navigator, sync-edit, and the full export pipeline.

---

## Technical Specs

### Carousel Data Model

```swift
// Already defined in Step 00 — activate these fields now
extension CollageProject {
    var carouselFrames: [CarouselFrame] { ... }  // ordered array of frames
}

@Model class CarouselFrame {
    var id: UUID
    var index: Int                   // display order (0-based)
    var cells: [CollageCell]         // photo, text, sticker zones per frame
    var backgroundOverride: Background?  // nil = use template default
}
```

### Four Carousel Types

**1. Panoramic Carousel**
A single wide source photo (or multiple photos stitched) split into N equal-width frames. When the user swipes through Instagram, the image appears to scroll continuously.

- Split axis: horizontal (most common) or vertical
- Source: one wide photo, or N photos stitched side-by-side by the app
- Output: N frames, each exactly `canvasWidth` × `canvasHeight`, cut at equal intervals
- Edge constraint: pixel columns at frame boundaries must match exactly (0px gap, 0px overlap)

**2. Matched Carousel**
Each frame is independently composed but shares a visual design system (same layout, font, color palette). Common for product carousels, tip lists, and "swipe for more" posts.

- User fills each frame individually
- **Sync edit** applies a change (background color, font) to all frames at once
- Frames can have different photos but same structural template

**3. Scroll-Through Story**
Sequential narrative frames with a photo + caption text block per frame. Common format: "5 things I learned", "before / after", tutorial steps.

- Each frame: full-bleed photo (top 70–80%) + text block (bottom 20–30%)
- Text block has a consistent background (solid, gradient, or frosted)
- Swipe animation makes the story feel like a reveal

**4. Grid Preview Carousel**
Frame 1: full multi-photo grid visible all at once. Frames 2–N: each frame zooms into one individual cell of that grid. Designed to tease the full grid before revealing each photo.

- Frame 1 is generated from the full collage (reuse Step 01 grid renderer)
- Frames 2–N: crop and expand each cell to full-canvas size with a smooth zoom effect baked in

### PanoramicStitcher

```swift
struct PanoramicStitcher {
    // Split a single CGImage into N equal-width frames
    func split(image: CGImage, into frameCount: Int, axis: SplitAxis) -> [CGImage]
    
    // Stitch N images side-by-side into one wide image
    func stitch(images: [CGImage], axis: SplitAxis) -> CGImage
    
    // Verify edges: last column of frame N matches first column of frame N+1
    func verifyEdgeAlignment(frames: [CGImage]) -> Bool
}
```

Use `vImage` for high-performance pixel operations. No tolerance — edge alignment must be exact.

### CarouselService

```swift
class CarouselService {
    func buildPanoramicCarousel(from image: CGImage, frameCount: Int, ratio: AspectRatio) -> [CarouselFrame]
    func buildMatchedCarousel(template: CarouselTemplate, frameCount: Int) -> [CarouselFrame]
    func buildScrollThroughCarousel(frameCount: Int, ratio: AspectRatio) -> [CarouselFrame]
    func buildGridPreviewCarousel(gridProject: CollageProject) -> [CarouselFrame]
    
    func syncEdit(change: StyleChange, to frames: [CarouselFrame]) -> [CarouselFrame]
    func reorder(frames: [CarouselFrame], from: Int, to: Int) -> [CarouselFrame]
}
```

---

## Checklist

### Carousel Service & Stitcher
- [ ] Create `Core/Services/CarouselService.swift`
- [ ] Create `Core/Rendering/PanoramicStitcher.swift`
- [ ] Implement `split(image:into:axis:)` using `vImage_Buffer` for exact pixel slicing
- [ ] Implement `stitch(images:axis:)` for panoramic source assembly
- [ ] Implement `verifyEdgeAlignment(frames:)` — pixel diff between adjacent frame edges must be 0
- [ ] Implement `syncEdit(change:to:)` — `StyleChange` enum covers: `.backgroundColor`, `.font`, `.textColor`, `.borderWidth`
- [ ] Implement `reorder(frames:from:to:)` — pure function, returns new ordered array

### Carousel Editor UI (UIKit)
- [ ] Create `Features/CarouselEditor/CarouselEditorViewController.swift`
- [ ] Top toolbar: **Back**, **Undo**, **Redo**, **Preview**, **Export**
- [ ] Center canvas: same UIKit `CanvasView` (CAMetalLayer) — renders the currently selected frame; reuses `TemplateEditorViewController` content
- [ ] **Frame Navigator** (bottom strip, `UICollectionView` horizontal):
  - `UICollectionViewCompositionalLayout` configured as a horizontal strip
  - Currently selected frame is highlighted via cell selection
  - Tap thumbnail → jump to that frame
  - Long-press + drag thumbnail → reorder frames (use `UICollectionView`'s built-in `beginInteractiveMovementForItem(at:)`)
  - `+` button as a supplementary item at the trailing edge → add a new frame (up to 10)
  - Trailing swipe action on cell → delete frame (with confirmation if frame has content)
- [ ] **Sync Edit toggle** (`UISwitch` in toolbar with adjacent label):
  - When ON: edits to background color, font, border apply to ALL frames simultaneously
  - When OFF: edits apply to current frame only
  - Toggle state visible from any frame

### Carousel Type Selector (SwiftUI — simple form, no canvas)
- [ ] Create `Features/CarouselEditor/CarouselTypeSelectorView.swift` (SwiftUI — this is a one-tap selection screen with no complex gestures)
- [ ] Present via `UIHostingController` from the coordinator
- [ ] 4 cards with illustration, name, and description for each type
- [ ] Panoramic: additional options — frame count (2–10) and split axis (horizontal/vertical)
- [ ] Matched/Scroll-through: frame count picker (2–10)
- [ ] Grid Preview: auto-derives frame count from grid cell count

### Panoramic Source Picker
- [ ] For panoramic type: after selecting frame count, show source picker:
  - Option A: "Pick one wide photo" — standard photo picker, single select
  - Option B: "Pick N photos to stitch" — picker with exact N selection, then stitch them
- [ ] After picking: run `PanoramicStitcher.split()` → show each resulting frame in the navigator
- [ ] Verify edge alignment; if it fails, show a warning (shouldn't happen with exact math, but guard it)

### Carousel Preview Player (UIKit)
- [ ] Create `Features/CarouselEditor/CarouselPreviewViewController.swift`
- [ ] Use `UIPageViewController` (`.scroll` transition style) — gives native Instagram-style swipe physics out of the box, far better than a SwiftUI `TabView` for this purpose
- [ ] Full-screen modal presentation with optional phone-bezel mockup
- [ ] Frame counter "1 / 6" overlay (toggleable via tap)
- [ ] **Export from preview**: Export button accessible here too — user should not have to go back to export
- [ ] Page indicator (`UIPageControl`) at the bottom mirrors the page state

### Safe-Zone Overlay (NEW — chart-topper feature)
- [ ] Add a **Safe-Zone overlay** toggle in the carousel editor toolbar
- [ ] When ON: dim regions of the canvas where Instagram/TikTok UI covers the design (top status bar, caption area, bottom interaction bar)
- [ ] Presets: Instagram Story, Instagram Reels, TikTok, Generic
- [ ] Overlay is preview-only — never exported into the final file
- [ ] Helps users avoid placing text/photos behind platform UI

### 20 Bundled Carousel Templates (JSON files)
- [ ] 5 Panoramic (`carousel_panoramic_travel.json`, etc.) — primarily 4:5 and 9:16
- [ ] 6 Matched (`carousel_matched_product.json`, `carousel_matched_tips.json`, etc.)
- [ ] 5 Scroll-Through Story (`carousel_story_tutorial.json`, etc.)
- [ ] 4 Grid Preview (`carousel_gridpreview_4cell.json`, etc.)

### Carousel Export
- [ ] Export sheet for carousel (different from single-image export):
  - **As images:** Export each frame as a numbered JPEG/PNG into a ZIP file
  - **As video slideshow:** Render frames as a video with configurable transition (crossfade, slide)
- [ ] "As images" export: `frame_01.jpg` ... `frame_N.jpg` in a ZIP
- [ ] ZIP saved to Files app (not Camera Roll — Camera Roll doesn't support folders)
- [ ] "As video" export: uses AVFoundation (Step 04's VideoComposer); returns a standard MP4

---

## Unit Tests — New Files

**`ClaudeCollageTests/Unit/CarouselStitcherTests.swift`:**
- [ ] `testSplitProducesCorrectFrameCount()` — `split(image:into: 5)` returns exactly 5 CGImages
- [ ] `testSplitFrameWidthsAreEqual()` — each frame is `sourceWidth / 5` pixels wide
- [ ] `testEdgeAlignmentPassesOnPerfectSplit()` — `verifyEdgeAlignment` returns `true` after a clean split
- [ ] `testStitchRoundTrip()` — split then stitch returns an image equal to the original
- [ ] `testReorderUpdatesIndices()` — move frame 0 to index 2; verify index values are 0,1,2
- [ ] `testSyncEditAppliesBackgroundToAllFrames()` — sync background change; all frames updated
- [ ] `testAddFrameIncreasesCountByOne()` — start with 3 frames; add 1; count = 4
- [ ] `testDeleteFrameDecreasesCountByOne()` — start with 4 frames; delete index 1; count = 3

**`ClaudeCollageTests/Integration/TemplateServiceTests.swift` (extend):**
- [ ] `testCarouselTemplatesLoadFromBundle()` — at least 15 carousel templates found
- [ ] `testPanoramicTemplateParsesFrameCount()` — `"frameCount": 5` maps to integer 5

Run: `Cmd+U` → all pass.

---

## Internal Alpha Build — Pillars 1 + 2 Complete

After Step 03b, refresh the internal alpha for team review. (External TestFlight + creator-beta cohorts live in Step 06 / Deployment.)

- [ ] Bump version to `0.2.0 (2)`
- [ ] Build with Debug scheme; install via Xcode on test devices
- [ ] Team review focus: carousel swipe feel, panoramic edge alignment, sync-edit discoverability, safe-zone overlay accuracy

---

## Done Criteria

- [ ] All four carousel types can be created end-to-end from type selection to export
- [ ] Panoramic carousel: pixel-perfect edge alignment verified by `verifyEdgeAlignment()`
- [ ] Frame navigator: reorder, add, delete all work with undo support
- [ ] Sync edit correctly propagates to all frames; non-sync edits stay local
- [ ] Carousel preview player swipes smoothly at 60fps
- [ ] Export as images: ZIP contains correctly named and correctly dimensioned frames
- [ ] Export as video slideshow: valid MP4 playable in Photos app
- [ ] All 10 unit + integration tests pass
