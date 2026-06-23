# Step 04 — Video Collage Editor + Social Media Export
**Part:** 1 — Development
**Weeks:** 23–30
**Depends on:** Step 03b complete
**Unlocks:** Step 05

---

## Goal

Build the video collage editor supporting mixed photo + video cells, and ship a unified social-media-ready export system that works across **all three pillars**. The export system is the most important deliverable of this step — it must be accessible at any point during editing and must produce platform-correct files in standard formats with all effects, text, stickers, and transitions composited into the output.

---

## Two Deliverables in This Step

1. **Video Collage Editor** — cells that contain video clips, with trim controls, audio mixing, and animated transitions
2. **Universal Social Media Export System** — a unified export sheet with platform presets, available from every editor at any time

Both are built in this step. The export system updates all previous editors (Grid, Template, Carousel) to use it.

---

## Part A: Video Collage Editor

### Technical Architecture

The video pipeline uses a direct `AVAssetReader` → `AVAssetWriter` approach. No `AVAssetExportSession` presets that might downsample quality. No intermediate temp files that bloat storage.

```
Video Cell Assets (AVAsset per cell)
         ↓
AVMutableComposition
(assembles clips into a single timeline,
 applies trim in/out points per clip)
         ↓
AVVideoCompositionCoreAnimationTool
(composites cell frames, text overlays,
 sticker overlays, transition effects)
         ↓
AVAssetWriter (direct pixel write)
H.264 (1080p) or HEVC (4K premium)
         ↓
Output: .mp4 / .mov in Camera Roll
```

**Why not `AVAssetExportSession`?** Export sessions resample video through an internal pipeline that can introduce quality loss (this is SCRL's documented bug). Writing directly via `AVAssetWriter` preserves full fidelity.

### VideoComposer

```swift
class VideoComposer {
    // Build a composition from a CollageProject with video cells
    func compose(project: CollageProject) async throws -> AVMutableComposition
    
    // Render to file — full quality, direct write
    func export(
        composition: AVMutableComposition,
        to url: URL,
        preset: ExportPreset,
        progressHandler: @escaping (Float) -> Void
    ) async throws
    
    // Preview: lower resolution render for in-app playback
    func previewPlayer(for composition: AVMutableComposition) -> AVPlayer
}
```

### Checklist — Video Editor

- [ ] Create `Core/Rendering/VideoComposer.swift`
- [ ] Video cell loading: `AVURLAsset` from `PHAsset` via `PHImageManager.requestAVAsset`
- [ ] `AVMutableComposition` assembly: place each cell's clip at the correct time range and video track
- [ ] Cell layout: use `AVMutableVideoCompositionInstruction` + `AVMutableVideoCompositionLayerInstruction` to apply affine transforms that position each cell in the canvas grid
- [ ] Trim control per cell: in/out scrubber (show video thumbnail strip; drag handles)
- [ ] Video loop: if cell clip is shorter than the composition duration, loop it with `AVMutableComposition.insertTimeRange(_:of:at:)`
- [ ] Mute toggle per cell
- [ ] Per-cell volume slider (0.0–1.0) via `AVMutableAudioMix`
- [ ] Background music track: import from Files app or Music app; trim to composition duration
- [ ] **Auto-beat-sync** (CapCut-style): analyze audio onsets via `AVAudioEngine` + onset detection; offer to align cell transitions to the beat with one tap. Premium feature for advanced sync; basic onset detection runs free.
- [ ] **Live Photo / motion sticker import**: detect Live Photos from picker; preserve their motion as a short looping video clip inside the cell
- [ ] Animated cell transitions:
  - `.crossfade` — opacity blend between incoming/outgoing cell layers
  - `.slideLeft` / `.slideRight` — translate X transform over transition duration
  - `.zoomIn` — scale transform from 0.9 → 1.0
  - Apply via `CALayer` animation injected into `AVVideoCompositionCoreAnimationTool`
- [ ] Mixed photo + video: photo cells are treated as static video tracks (generate `CMSampleBuffer` from `UIImage` at canvas frame rate)
- [ ] Video collage preview: `AVPlayer` instance inside an `AVPlayerLayer` — plays the composed video in real time before export

### Video Editor UI (UIKit — required for AVPlayerLayer)
- [ ] Create `Features/VideoEditor/VideoEditorViewController.swift`
- [ ] Create `Features/VideoEditor/VideoCanvasView.swift` — `UIView` whose `layerClass` is `AVPlayerLayer`. Hosting an `AVPlayerLayer` inside SwiftUI requires a `UIViewRepresentable` bridge that gets messy with player lifecycle and KVO; UIKit owns it cleanly.
- [ ] Top toolbar: **Back**, **Undo**, **Redo**, **Preview**, **Export** ← Export always visible
- [ ] Center: `VideoCanvasView` filling available space
- [ ] Cell selection: hit-test on the canvas → highlight selected cell → show cell controls
- [ ] Per-cell controls panel (slide-up via `UISheetPresentationController`):
  - Video thumbnail strip — `UICollectionView` horizontal with frame thumbnails generated via `AVAssetImageGenerator`
  - Trim handles — custom `UIView` subclass with `UIPanGestureRecognizer` on each handle
  - Loop toggle (SwiftUI inside the sheet — simple toggle, hosted via `UIHostingController`)
  - Mute / Volume slider (SwiftUI)
  - Replace video button (`UIButton` action presents `PHPickerViewController` configured for `.videos`)
  - Transition picker (UIKit `UICollectionView` horizontal of transition thumbnails)
- [ ] Global controls panel:
  - Background music track (add / remove) — opens `MPMediaPickerController` or Files picker
  - Global volume balance (cells vs. music) — SwiftUI dual-slider in a hosted sheet
  - Duration display (auto-calculated from longest cell)

---

## Part B: Universal Social Media Export System

This is the most critical deliverable of the entire project. It replaces the simple export sheet from Step 01 with a full-featured export system shared by all editors.

**Framework choice:** The export sheet is a structured **form** with platform tiles, presets, and option toggles — no complex gestures, no canvas. **SwiftUI is the right tool here.** Implement `UniversalExportSheetView` in SwiftUI and present it from each UIKit editor via `UIHostingController` + `UISheetPresentationController` (medium and large detents).

### Design Principle
The export button must be accessible **at any point during editing** — not just after the user "finishes." A user should be able to tap Export after placing 2 photos and get a valid shareable result, just as they can in SCRL. Saving a draft and exporting happen independently.

### Export Sheet — Full Specification

When the user taps **Export** from any editor (Grid, Template, Carousel, or Video), the same export sheet slides up. It has three sections:

---

#### Section 1: Platform / Format Preset

A row of platform icon buttons. Selecting a preset auto-fills the settings below.

| Preset | Icon | Canvas ratio enforced | Video format | Resolution | Notes |
|--------|------|--------------------|-------------|-----------|-------|
| **Instagram Post** | Instagram logo | 1:1 or 4:5 | MP4 H.264 | 1080p | Matches IG feed spec |
| **Instagram Story** | Phone icon | 9:16 | MP4 H.264 | 1080×1920 | Also correct for TikTok, Reels |
| **TikTok** | TikTok logo | 9:16 | MP4 H.264 | 1080×1920 | Identical to IG Story spec |
| **YouTube** | YouTube logo | 16:9 | MP4 H.264 | 1920×1080 | Landscape standard |
| **Twitter / X** | X logo | 16:9 | MP4 H.264 | 1280×720 | Twitter's preferred resolution |
| **WhatsApp** | WhatsApp logo | 9:16 or 1:1 | MP4 H.264 | 1080p | Status + chat |
| **Print** | Printer icon | 4:3 or user-defined | JPEG | 300 DPI equivalent | Photo print quality |
| **Custom** | Sliders icon | Current canvas | User-chosen | User-chosen | Override all settings |

When a preset is selected that doesn't match the current canvas ratio, show a warning: *"Your canvas is 1:1 but Instagram Story requires 9:16. Export anyway, or change the canvas size?"* with two options: **Export Anyway** and **Resize Canvas**.

---

#### Section 2: Quality Settings

Shown below the platform row. Auto-filled by preset but user-adjustable:

**For image output:**
- Format: JPEG / PNG (PNG is always shown; selecting PNG disables quality slider)
- Quality: slider 50% – 100% (maps to `CGImageDestination` compression quality 0.5–1.0)
- Resolution: **Full** (native canvas px) / **Half** / **Custom px**

**For video output:**
- Format: **MP4 (H.264)** (default, maximum compatibility) / **MOV (HEVC)** (premium only — smaller file, same quality)
- Resolution: **1080p** (free) / **4K** (premium)
- Frame rate: **Match source** (default) / **30fps** / **60fps**
- All applied effects baked in: filters ✓, text overlays ✓, stickers ✓, transitions ✓ — these are non-negotiable and always composited

*Note: "All effects baked in" is not a user toggle — it is always true. The export always reflects exactly what the preview shows.*

---

#### Section 3: Export Actions

Two buttons at the bottom of the sheet:

**Save to Photos**
- Saves to Camera Roll
- Photos: via `PHPhotoLibrary.performChanges`
- Videos: via `PHPhotoLibrary.performChanges` + `PHAssetCreationRequest.creationRequestForAssetFromVideo`
- Shows progress bar for video exports
- On success: "Saved to Photos" toast + haptic success feedback
- On failure: alert with error message + retry option

**Quick Share**
- Opens iOS Share Sheet (`UIActivityViewController`) immediately after export completes
- Pre-selects the platform app if installed (Instagram, TikTok, etc.) using URL scheme check
- For Instagram: exports to Files first, then opens Instagram's share intent
- User can share to any app in the share sheet (Messages, AirDrop, Mail, etc.)

**Additional options (accessible via "⋯ More" button):**
- Save to Files app
- Copy to clipboard (image only)
- AirDrop directly

---

#### Export Progress UX
- Indeterminate spinner for < 3 seconds
- Progress bar (0–100%) for video exports > 3 seconds
- "Processing..." label with elapsed time
- Cancel button available during video export (calls `AVAssetWriter.cancelWriting()`)
- The sheet stays open during export — user cannot accidentally dismiss it
- **Live Activity** (ActivityKit) starts when a video export begins:
  - Shows progress on the Lock Screen
  - Compact + expanded Dynamic Island layouts on iPhone 14 Pro+
  - Auto-dismisses on export completion (or 8h timeout safety)
  - This is a chart-topper feature — CapCut, InShot, and Photoroom all do this

---

### Applying Overlays to Video Export

All of these must be composited into the video file (not added as a separate layer in the player):

| Overlay type | How to composite into video |
|-------------|---------------------------|
| Text overlays | `CATextLayer` injected via `AVVideoCompositionCoreAnimationTool` |
| Sticker overlays | `CALayer` with the sticker image, injected the same way |
| Filter adjustments per cell | Apply `CIFilter` chain to each cell's `CMSampleBuffer` via `AVVideoCompositionCustomVideoCompositing` |
| Border/gap between cells | Rendered into the base composition layer geometry |
| Background color/gradient | Bottom `CALayer` fill |
| Transitions | `CABasicAnimation` on opacity/transform, injected via `AVVideoCompositionCoreAnimationTool` |

### Export the Existing Editors

Update the export button in all prior editors to present `UniversalExportSheetView` via `UIHostingController`:
- [ ] `GridEditorViewController` → presents the sheet with image-only options
- [ ] `TemplateEditorViewController` → same
- [ ] `CarouselEditorViewController` → same, with "As images ZIP" option exposed
- [ ] `VideoEditorViewController` → same, with video-specific options exposed

---

## Unit Tests

**`ClaudeCollageTests/Integration/ExportServiceTests.swift`:**
- [ ] `testImageExportProducesCorrectDimensions()` — export 1080×1080 canvas → output JPEG is 1080×1080
- [ ] `testJPEGQualitySettingApplied()` — quality 0.5 produces smaller file than quality 1.0
- [ ] `testPNGExportIsLossless()` — re-read exported PNG → pixel values match source render
- [ ] `testVideoExportProducesMp4()` — exported file has `.mp4` extension and valid UTI
- [ ] `testVideoExportDimensionsMatchPreset()` — 1080p preset → output video track is 1920×1080 (for 16:9) or 1080×1920 (for 9:16)
- [ ] `testAllOverlaysAreBakedIntoVideoExport()` — add a text overlay; export; inspect output frames via `AVAssetReader`; text pixels present

Run: `Cmd+U` → all pass.

---

## Done Criteria

**Video editor:**
- [ ] Mixed photo + video collage plays smoothly in the in-editor preview
- [ ] Trim, loop, mute, and volume controls work per cell
- [ ] Animated transitions render correctly in the preview and in the export
- [ ] Background music mixes with cell audio

**Export system:**
- [ ] Export button is visible in the toolbar of every editor at all times
- [ ] Selecting any platform preset auto-configures resolution and format correctly
- [ ] Mismatched canvas ratio shows a warning before export
- [ ] All effects (filters, text, stickers, transitions) are present in the exported file
- [ ] Video exports via direct `AVAssetReader/Writer` — no `AVAssetExportSession` quality degradation
- [ ] Progress indicator shown for all video exports; cancel works cleanly
- [ ] Quick Share opens the iOS share sheet with the exported file immediately
- [ ] All 6 integration tests pass

**Quality bar:**
- [ ] Export a 30-second video collage; play it back in Photos; it matches the in-app preview exactly
- [ ] Export quality test: import a 4K source video, export at 1080p — output should not be softer than a native 1080p source at the same content
