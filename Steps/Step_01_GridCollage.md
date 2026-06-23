# Step 01 — Grid & Rectangular Collage Editor
**Part:** 1 — Development
**Weeks:** 3–7
**Depends on:** Step 00 complete
**Unlocks:** Step 02

---

## Goal

Build a fully working rectangular grid collage editor — the foundation that every other editor mode builds on. By the end of this step, a user can pick photos, arrange them in a grid, adjust borders and backgrounds, and export a finished image to their Camera Roll.

---

## Technical Specs

### CollageLayoutEngine
A pure Swift struct (no UIKit, no SwiftUI) that computes the frame of each cell given a layout type and canvas size. Pure functions only — easy to unit test.

```swift
struct CollageLayoutEngine {
    func layout(for template: GridTemplate, canvasSize: CGSize) -> [CellFrame]
}

struct CellFrame {
    let id: String
    let frame: CGRect        // absolute pixel coordinates
    let shape: CellShape     // .rectangle for Step 01
    let clipPath: CGPath?    // nil for rectangles
}
```

### Metal Compositor
Renders an array of `CellFrame` + assigned photos into a single `CGImage`. Runs on the GPU via Metal. A UIKit `UIView` subclass backed by `CAMetalLayer` displays this as a live preview (no `UIViewRepresentable` wrapper — direct UIKit hosting).

Key rules:
- Renders at preview resolution (screen scale, max 1080px wide) for the live canvas
- Renders at full export resolution only when the user taps Export
- Each cell's photo is pan/zoom/rotated using an affine transform stored in `CollageCell`
- Cells are composited in index order (cell 0 rendered first, on the bottom)

```swift
// UIKit-native Metal canvas — no SwiftUI bridge
final class CollageCanvasView: UIView {
    override class var layerClass: AnyClass { CAMetalLayer.self }
    var metalLayer: CAMetalLayer { layer as! CAMetalLayer }
    // ... renderer wires into metalLayer.nextDrawable()
}
```

### Undo/Redo Stack
A simple value-type stack wrapping snapshots of `CollageProject`:
```swift
class UndoStack {
    private var history: [CollageProject] = []
    private var index: Int = 0
    func push(_ state: CollageProject)
    func undo() -> CollageProject?
    func redo() -> CollageProject?
    var canUndo: Bool
    var canRedo: Bool
}
```
Maximum 20 snapshots. Older snapshots are dropped when limit is exceeded.

### Photo Picker
Use `PHPickerViewController` directly from UIKit (iOS 14+). **No photo library permission required** — the picker runs out-of-process and only delivers the photos the user explicitly selected. This is a huge UX win: no permission prompt, no deny risk.

```swift
import PhotosUI

var config = PHPickerConfiguration()
config.selectionLimit = 9
config.filter = .images
let picker = PHPickerViewController(configuration: config)
picker.delegate = self  // PHPickerViewControllerDelegate
present(picker, animated: true)
```

Load each `PHPickerResult` via `itemProvider.loadObject(ofClass: UIImage.self)`. For drag/drop and share-extension flows, conform cells to accept `UIImage` via `UIDropInteraction`.

*Why not SwiftUI `PhotosPicker`?* The editor is UIKit, and presenting a `PHPickerViewController` directly is cleaner than bridging through `UIHostingController` for a one-shot modal. It's also the API SwiftUI's `PhotosPicker` wraps internally — same underlying behavior, no permission required.

---

## Checklist

### Layout Engine
- [ ] Create `Core/Rendering/CollageLayoutEngine.swift`
- [ ] Implement layouts for these 8 grid types:
  - `.oneCell` — single full-canvas photo
  - `.twoUpHorizontal` — left/right halves
  - `.twoUpVertical` — top/bottom halves
  - `.threeLeft` — one tall left + two stacked right
  - `.threeRight` — two stacked left + one tall right
  - `.fourSquare` — 2×2 equal grid
  - `.sixGrid` — 2×3 equal grid
  - `.nineGrid` — 3×3 equal grid
- [ ] Border/gap: subtract `borderWidth` from each cell's frame, applied uniformly
- [ ] All frames normalized to canvas size (pass `CGSize`, get back `CGRect` in absolute pixels)
- [ ] Clamp: no cell frame can have negative width or height

### Metal Compositor
- [ ] Create `Core/Rendering/CollageRenderer.swift`
- [ ] Set up a `MTLDevice`, `MTLCommandQueue`, and reusable `MTLRenderPassDescriptor`
- [ ] For each cell: sample the photo texture with the cell's `CellTransform` (pan, zoom, rotation)
- [ ] Composite all cells onto a white background (default)
- [ ] Output: `CGImage` at the requested resolution
- [ ] Preview path: runs async, updates a `@Published var previewImage: CGImage?` in the ViewModel
- [ ] Export path: runs synchronously on a background thread at full resolution

### Photo Picker & Import
- [ ] Present `PHPickerViewController` directly from `GridEditorViewController`
- [ ] Multi-select up to 9 photos at once via `PHPickerConfiguration.selectionLimit = 9`
- [ ] Load each `PHPickerResult` asynchronously via `itemProvider.loadObject(ofClass: UIImage.self)`; show a per-cell spinner while loading
- [ ] Store the loaded image data in an `NSCache`; persist a local file URL in `CollageCell.photoAssetID`
- [ ] Load full-resolution image on demand for export; cache a smaller preview for the live canvas
- [ ] Attach a `UIDropInteraction` to each cell view to support drag/drop from Files, Safari, Messages, Photos (UIKit `UIDropInteractionDelegate`)

### Grid Editor UI (UIKit)
- [ ] Create `Features/GridEditor/GridEditorViewController.swift` (subclass `UIViewController`)
- [ ] Create `Features/GridEditor/GridEditorViewModel.swift` (`@Observable` final class — pure Swift, no UIKit imports)
- [ ] Create `Features/GridEditor/CanvasView.swift` (`UIView` backed by `CAMetalLayer`)
- [ ] Layout via Auto Layout (`NSLayoutAnchor`); no Storyboard
- [ ] Top toolbar (`UINavigationBar` or custom UIToolbar): **Back**, **Undo**, **Redo**, **Export**
- [ ] Center: `CanvasView` filling available space
- [ ] Bottom toolbar (UIKit container):
  - **Layout picker** — `UICollectionView` (horizontal, `UICollectionViewCompositionalLayout`) of grid layout thumbnails
  - **Border** slider (`UISlider`, 0–20pt)
  - **Background** picker (`UICollectionView` color swatch row)
- [ ] Tap empty cell → present `PHPickerViewController`
- [ ] Tap filled cell → show cell action sheet (`UIAlertController .actionSheet`): **Replace Photo**, **Edit Cell**, **Clear**
- [ ] Long-press + drag cell → swap cell positions using `UIDragInteraction` + `UIDropInteraction`

### Cell-Level Editor (slide-up panel)
- [ ] `Features/GridEditor/CellGestureController.swift` — composes `UIPanGestureRecognizer`, `UIPinchGestureRecognizer`, `UIRotationGestureRecognizer` with `simultaneousRecognition` so all three work together on the same cell
- [ ] Pan/zoom/rotate photo within cell; updates the cell's affine transform in the view model
- [ ] Filter strip — small SwiftUI subview embedded via `UIHostingController` (it's a simple form, SwiftUI is genuinely simpler here)
- [ ] Filter sliders adjust `CellFilters` in real time
- [ ] **Done** button closes the panel and updates the preview

### Project Save / Resume
- [ ] Auto-save to SwiftData every time `CollageProject` mutates (use `.onChange` or Combine sink)
- [ ] Home screen shows saved projects as thumbnail cards
- [ ] Tap a card → resume editing

### Export (Image)
- [ ] Export button in toolbar → show export sheet
- [ ] Export sheet options:
  - **Format:** JPEG (default) / PNG
  - **Quality:** High (JPEG 0.9) / Maximum (JPEG 1.0) — PNG is always lossless
  - **Size:** Full resolution / Half resolution
- [ ] Progress indicator during export (it's fast but show it anyway)
- [ ] On success: "Saved to Photos" toast + haptic feedback
- [ ] On failure: alert with error message
- [ ] Request `NSPhotoLibraryAddUsageDescription` permission before saving

---

## Unit Tests — `ClaudeCollageTests/Unit/CollageLayoutEngineTests.swift`

Write these tests as you build the layout engine (not after):

- [ ] `testTwoUpHorizontalProducesEqualHalves()` — each cell is exactly 50% canvas width
- [ ] `testFourSquareProducesEqualQuarters()` — each cell is exactly 25% canvas area
- [ ] `testBorderReducesCellSize()` — a 4pt border reduces each cell by 4pt on shared edges
- [ ] `testNoCellHasNegativeFrame()` — border larger than cell size → clamped to zero, no crash
- [ ] `testAllCellsCoverCanvasExactly()` — sum of all cell areas + gaps equals total canvas area
- [ ] `testLayoutEngineIsIdempotent()` — calling layout() twice with same inputs returns identical results
- [ ] `testUndoStackPushAndPop()` — push 3 states, undo 2, verify current is state 1
- [ ] `testUndoStackMaxLimitDropsOldest()` — push 21 states, verify stack holds only 20

Run: `Cmd+U` → all pass before moving on.

---

## Done Criteria

- [ ] User can create a new project, pick up to 9 photos, arrange in any of 8 grid layouts
- [ ] Per-cell pan/zoom/rotate and filter adjustments work smoothly at 60fps on iPhone 13+
- [ ] Multi-gesture composition (pan + pinch + rotate simultaneously) is precise — no gesture stealing
- [ ] Border and background controls update the preview in real time
- [ ] Project auto-saves and resumes correctly
- [ ] Exported JPEG appears in Camera Roll at the correct pixel dimensions
- [ ] All 8 unit tests pass
- [ ] No force-unwraps in `CollageLayoutEngine.swift` or `CollageRenderer.swift`
- [ ] Memory usage during editing stays below 200 MB (check in Instruments → Allocations)
- [ ] UIKit `GridEditorViewController` is reachable via the `AppCoordinator`; no orphan SwiftUI navigation
