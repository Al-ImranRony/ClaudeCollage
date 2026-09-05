# Editor redesign: collage canvas and video timeline

**Date:** 2026-09-05
**Status:** Approved, ready for implementation planning
**Scope:** A shared editor chrome, adopted by both remaining unstyled screens — `GridEditorViewController` ("Grid Collage") and `VideoEditorViewController` ("Video Collage") — plus a parallel-lane timeline and timed, styled text for the video editor.

---

## 0. Why now

Every other surface has been through the design system. These two editors are the last
screens that still look like the scaffold they were built as, and they are the screens a
user spends the most time on. Two concrete failures drive the work:

- A 9:16 "Story" collage draws at **208 × 370pt** inside a 370 × 370 box — 44% of the
  canvas view can never show anything.
- "Edit video with text" is not currently expressible: `TextOverlay` has no time fields,
  so text is burned across the entire export.

---

## 1. The shared editor chrome

Three new components under `Caroullage/Core/DesignSystem/Editor/`. Both editors are built
from them, which is what makes the two screens read as one app.

### 1.1 `EditorStage`

Hosts the canvas and owns its geometry.

```swift
final class EditorStage: UIView {
    func setContent(_ view: UIView)
    /// Rebuilds the stored width/height multiplier constraint from the document size.
    func setCanvasAspect(_ canvasSize: CGSize)
}
```

The content view is centred, pinned to a minimum 16pt horizontal / 8pt vertical inset,
and constrained to the document's aspect ratio via a **stored, replaceable** multiplier
constraint. The stage fills all space between the navigation bar and whatever is beneath
it, so it grows and shrinks as panels open and close.

### 1.2 `EditorToolRail`

The bottom rail. Holds a base tool set and can insert a contextual group ahead of it
without losing the base tools — the "A + C" decision.

```swift
struct EditorTool: Equatable {
    let id: String
    let title: String
    let systemImage: String
    let accessibilityIdentifier: String
}

struct EditorRailContext: Equatable {
    let chipTitle: String          // "Photo", "Text", "Clip 1"
    let chipSystemImage: String
    let tools: [EditorTool]
}

final class EditorToolRail: UIView {
    var onSelect: ((EditorTool.ID) -> Void)?
    var onDismissContext: (() -> Void)?

    func setBaseTools(_ tools: [EditorTool])
    func setContext(_ context: EditorRailContext?)   // nil clears
    func setActiveTool(_ id: EditorTool.ID?)
}
```

Layout: a horizontally scrollable row, 52pt of content height. When a context is set, a
dismissible chip and the contextual tools are inserted at the leading edge, followed by a
hairline divider and the untouched base tools; the rail scrolls itself back to the leading
edge so the new tools are what the user sees.

The rail's **background** extends to the bottom screen edge; its **content** is laid out
inside the safe area. This preserves the intent of the current no-dead-band behaviour (see
§6.1) without the scroll view that behaviour was built around.

### 1.3 `EditorPanel`

The swap-in container above the rail.

```swift
final class EditorPanel: UIView {
    var onClose: (() -> Void)?
    var isPresenting: Bool { get }

    func show(_ content: UIView, title: String, animated: Bool)
    func hide(animated: Bool)
}
```

One tool's controls at a time, 100–140pt tall, with an uppercase title row and a close
control. Show and hide animate the panel's own height with `Theme.Motion.standard` and the
existing spring constants; the stage re-lays out in the same animation block, so the canvas
grows and shrinks smoothly rather than jumping.

---

## 2. The collage editor

### 2.1 The square-canvas bug

`CanvasView.layoutCellGeometry()` already aspect-fits its content with
`AVMakeRect(aspectRatio: model.canvasSize, insideRect: bounds)`. The only broken piece is
in the view controller:

```swift
// GridEditorViewController.swift:278
let canvasSquare = canvasView.heightAnchor.constraint(equalTo: canvasView.widthAnchor)
```

Replacing this with a multiplier constraint derived from `viewModel.canvasSize` — exactly
what `VideoEditorViewController.swift:158` already does correctly — makes `AVMakeRect` a
no-op that exactly fills the view. The constraint is stored and rebuilt through
`EditorStage.setCanvasAspect(_:)` whenever the document's canvas size changes.

Measured on a 402 × 874pt screen with a 9:16 document:

| | Canvas |
|---|---|
| Today | 208 × 370pt |
| Panel open | 335 × 596pt |
| Panel closed | 383 × 681pt |

### 2.2 Base rail

`Layout · Frame · Background · Text · Sticker`

| Tool | Panel |
|---|---|
| **Layout** | A `Grid / Shapes / Custom` segmented control over one horizontal strip. Replaces four separately-stacked rows (mode control, `LayoutPickerView`, `ShapePickerView`, custom-shape button). `Custom` carries the premium lock inline. The whole tool is hidden for `.template` documents, preserving `CollageLayout.offersLayoutAlternatives`. |
| **Frame** | The existing Border and Corners sliders, unchanged, including their proportional bounds from `maxBorderWidth` / `maxCornerRadius`. |
| **Background** | The existing swatch strip, with the AI generative-background entry as a trailing `✦` chip in the same strip rather than a separate row. |
| **Text** | Has no panel of its own. One tap adds a text zone at canvas centre, selects it, and lands directly in the text contextual state of §2.3 — an empty intermediate panel would be a wasted step. |
| **Sticker** | Opens the existing `StickerPickerViewController` sheet. |

### 2.3 Contextual groups

**Photo selected** — `Replace · Adjust · Lift · Erase · Clear`. This retires the
`UIAlertController` action sheet in `presentCellActions(for:)` entirely. `Adjust` shows
`FilterStripView` in the panel instead of a medium/large page sheet, so the cell being
filtered stays visible.

**Text selected** — `Edit · Style · Duplicate · Delete`, with the panel carrying sub-tabs
`Font / Style / Colour / Space` that map one-to-one onto `TextStyleSheet`'s existing
sections. The full sheet remains reachable as a **More** row for the long tail
(custom colour picker, fine spacing).

Selecting anything sets the rail context; the chip's `✕` and a tap on empty canvas both
clear it.

---

## 3. The video editor

Same nav bar, stage, rail and panel, plus one new component.

### 3.1 `VideoTimeline`

Sits between the stage and the panel. Two states, remembered per project.

**Collapsed (~56pt, the default).** Play control, current-time and duration readouts, one
summary filmstrip across the composition, the text pills, a single playhead, and a chevron.
Canvas: **358 × 637pt**.

**Expanded (~190pt).** A time ruler, then one lane per cell showing that clip's filmstrip,
then a text lane of pills, then a music lane — all under one playhead. Canvas:
**285 × 507pt**. A swipe on the strip toggles the state as well as the chevron.

Direct manipulation, replacing modal round-trips:

- drag a lane's ends → trim in/out
- drag a lane's body → delay when that cell starts (§3.3)
- drag a text pill → re-time it; drag its ends → change how long it holds
- drag the playhead → scrub, canvas following

The lanes are parallel because the composition is parallel: every clip is inserted at
`.zero` on its own track (`VideoCompositionBuilder.swift:330`). This is a collage, not a
sequence, and the timeline should say so.

### 3.2 Base rail and contextual groups

Base: `Layout · Frame · Text · Sticker · Audio` — deliberately symmetric with the collage
editor. `Frame` drives the existing `VideoEditorViewModel.borderWidth`.

**Clip selected** — `Swap · Trim · Volume · Transition · Clear`, backed by the values
`VideoCellControlsSheet` already edits (`trimStart`, `trimEnd`, `isLooping`, `isMuted`,
`volume`, `transitionStyle`, `transitionDuration`). The sheet stays as the **More**
destination; the rail and timeline cover the common path.

**Text selected** — `Edit · Style · Timing · Delete`. `Timing` offers numeric in/out entry
for users who want precision over dragging.

### 3.3 `startOffset` — the one flagged risk

`VideoCellState` gains `startOffset: Double`, and `VideoCompositionBuilder` inserts an
empty time range ahead of each clip. The total-duration maths, `BeatSyncPlanner`, and the
transition `startTime` logic must all agree with the new origin.

**This is built as the final slice of Plan 2.** If it proves hairy it can be dropped
without losing the release: the timeline still delivers trimming, text timing and
scrubbing, which is the whole visible win. Lanes simply all start at zero until it lands.

---

## 4. Text: timing and style

### 4.1 Model

All fields decode with fallbacks, matching the existing defensive `init(from:)` pattern in
`TextOverlay`, `EditorCellState` and `VideoCellState`. Every already-saved project renders
byte-identically after the change.

| Field | Default | Meaning |
|---|---|---|
| `TextOverlay.startTime: Double?` | `nil` | In-point in seconds. `nil` = from the beginning. |
| `TextOverlay.endTime: Double?` | `nil` | Out-point. `nil` = to the end. |
| `TextOverlay.style: TextStyle` | `.plain` | §4.2 |
| `TextOverlay.animation: TextAnimation` | `.none` | **Reserved.** Nothing reads it. It exists so tier-3 animation is later a renderer change, not a migration. |
| `VideoCellState.startOffset: Double` | `0` | §3.3 |

`nil` timing on a still collage is meaningless and simply ignored — the fields cost the
photo path nothing.

### 4.2 `TextStyle`

Tier 2: the treatments that make text legible over moving footage, shipped as one-tap
presets rather than five loose sliders.

```
plain · shadow · stroke · pill · highlight · glow
```

Each preset carries its own parameters (colour, width, inset).

> **Corrected during implementation (2026-09-06).** This section originally claimed all six
> presets are drawn in one place — `TextRendering.draw(_:in:fontScale:context:)` — so preview
> and export could not disagree. **That was false.** The live canvas never calls `draw`: it
> builds a `UILabel` from `TextRendering.attributedString(...)` (`CanvasView.swift:743`), while
> `draw` is reached only from `CollageRenderer` (photo export) and `VideoOverlayRenderer` (video
> export). Attribute-based treatments were fine; painted ones were not, so `.pill` and
> `.highlight` rendered *only after export* — a WYSIWYG break in the editor.

The presets split by what each treatment actually is, and parity is now structural:

- **`stroke`, `shadow`, `glow`** are `NSAttributedString` attributes set in `applyStyle`. Both
  the canvas and both exporters build their text from `attributedString`, so these agree for free.
- **`highlight`** is the `.backgroundColor` attribute. This is not a workaround but the better
  model: it is drawn **per line**, which is what a marker-pen highlight is, where a single
  block rectangle would band across the empty space beside a shorter second line.
- **`pill`** is the one genuinely painted background. Its geometry lives in one shared helper,
  `TextRendering.backgroundRect(for:in:fontScale:)`, called by both the exporter and the live
  canvas's `TextOverlayView` — so the two agree by construction rather than by coincidence.
  The rect is sized from the *measured* text and clamped to the overlay frame.

`TextStyle` still lands in Plan 1 with the collage editor rather than waiting for Plan 2: the
collage editor benefits identically, and the shared helpers are what guarantee preview == export.

### 4.3 Timed rendering

`VideoOverlayRenderer.overlayImage(...)` currently returns **one flat image** for the whole
export, composited through `AVVideoCompositionCoreAnimationTool`. Because that tool is
already in the pipeline, timing is a modest change rather than a new architecture: build a
`CALayer` per text overlay and drive its opacity with a keyframe animation
(`beginTime = AVCoreAnimationBeginTimeAtZero`, `fillMode = .both`,
`isRemovedOnCompletion = false`).

The renderer's entry point therefore changes from returning an image to returning a layer
tree; sticker overlays keep their existing always-on behaviour as a layer with no
animation. The live `VideoCanvasView` applies the same in/out points against the player's
current time so preview matches export.

---

## 5. Delivery

One spec, two implementation plans.

**Plan 1 — chrome and the collage editor.** `EditorStage`, `EditorToolRail`, `EditorPanel`;
the aspect-ratio fix; the collage editor rebuilt on the chrome; `TextStyle` and the shared
`TextRendering` draw path.

**Plan 2 — the video editor.** Adopt the chrome; `VideoTimeline` collapsed and expanded;
timed text and the layer-tree renderer; the audio and clip panels; `startOffset` last.

Plan 1 lands every shared component, so Plan 2 is mostly assembly.

---

## 6. Testing

### 6.1 `EditorControlTrayTests` — rewritten, not deleted

Its three tests assert that the first `UIScrollView` child of the editor's root view reaches
the bottom screen edge with zero `adjustedContentInset.bottom`. That was a guard against a
dead band under the old full-height scrolling tray. The intent survives; the shape does not.
The tests are rewritten against `EditorToolRail`: its background reaches
`view.bounds.maxY`, and its interactive content sits at or above the safe-area bottom. The
harness test (`testTheHarnessActuallyAppliesTheInset`) is kept as-is — it guards the fake
home indicator that makes the others non-vacuous.

### 6.2 UI test identifier continuity

Existing identifiers are **reused on the new rail tools** wherever the tool is the same
thing — `videoLayoutButton`, `videoMusicButton` (now `Audio`), `videoAddTextButton`,
`videoAddStickerButton`, `videoCanvas`, `videoExportButton`, `undoButton`, `exportButton`.
Four assertions depend on controls that are no longer always visible and must be updated:

| Test | Assertion | Change |
|---|---|---|
| `GridEditorFlowUITests.swift:35` | `staticTexts["Layout"].exists` | Target the rail's Layout button. |
| `GridEditorFlowUITests.swift:36` | `staticTexts["Background"].exists` | Target the rail's Background button. |
| `PolygonQAUITests.swift:55,85` | `collectionViews["layoutPicker"]` exists / does not | Open the Layout panel first; the picker now lives inside it. |
| `MagicEraserUITests.swift:48` | `generateBackgroundButton` does not exist | The button moved into the Background panel; assert against the opened panel. |

Per the project's XCUITest note, collection-view assertions stay on **identity, not
counts** — visible-cell counts saturate at what is on screen.

### 6.3 New coverage

- `EditorStage` produces the expected canvas rect for 1:1, 4:5, 9:16 and 16:9 documents,
  and updates when the aspect changes.
- `EditorToolRail` keeps base tools reachable when a context is inserted, and restores
  cleanly when it is cleared.
- `TextOverlay` round-trips the new fields, and a snapshot saved **without** them decodes
  to `nil` timing / `.plain` / `.none`.
- `TextStyle` renders identically through `TextRendering` for canvas and export scales.
- Timed overlays produce the right visibility at sampled composition times.
- `startOffset` (its own slice): total duration, beat-sync alignment and transition start
  times remain correct with a non-zero offset.

---

## 7. Out of scope

- **Tier-3 text animation** (fade / slide / pop / typewriter). The `animation` field is
  reserved for it; nothing reads it. Its own spec.
- **Changing a document's canvas ratio from inside the editor.** `CanvasPreset` is chosen
  at creation. Making it editable is a real gap but a separate feature, not a redesign.
- **A document-level "look" filter across all cells.** Tempting alongside the rail, but new
  functionality rather than re-homing existing functionality.
- Any change to export, purchase, or persistence behaviour beyond the additive model fields
  in §4.1.
