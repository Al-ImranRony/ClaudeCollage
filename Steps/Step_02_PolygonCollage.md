# Step 02 — Polygon & Shape Collage
**Part:** 1 — Development
**Weeks:** 8–12
**Depends on:** Step 01 complete
**Unlocks:** Step 03a

---

## Goal

Extend the collage editor to support non-rectangular cell shapes — diagonals, triangles, hexagons, circles, and custom bezier splits. Everything built in Step 01 (Metal compositor, undo/redo, export, SwiftData) is reused. Only the layout engine and rendering masks need to change.

---

## Technical Specs

### CGPath-Based Cell Masking
Each `CellFrame` already has a `clipPath: CGPath?` field (set to `nil` in Step 01 for rectangles). For polygon cells, populate this with the exact `CGPath` that defines the cell boundary. The Metal compositor clips each cell's texture to its `clipPath` using a stencil buffer.

```swift
// In CollageLayoutEngine — polygon variant
func polygonLayout(for template: PolygonTemplate, canvasSize: CGSize) -> [CellFrame]

// CellFrame.clipPath is non-nil for all polygon cells
// The path is in absolute pixel coordinates matching the canvas
```

### Polygon Layout Types

| Shape | Description | Cell count |
|-------|-------------|-----------|
| `.diagonalLeft` | Canvas split by a line from top-left to bottom-right | 2 |
| `.diagonalRight` | Split by a line from top-right to bottom-left | 2 |
| `.triangleTop` | Top triangle + bottom rectangle | 2 |
| `.triangleCenter` | Center triangle + 3 corner fills | 4 |
| `.hexagonGrid` | 7-cell honeycomb (1 center + 6 surrounding) | 7 |
| `.circleCenter` | Circle in center + 4 corner fills | 5 |
| `.doubleCircle` | Two equal circles side by side with background fill | 3 |
| `.arrowLeft` | Left-pointing arrow shape + fill | 2 |
| `.arrowRight` | Right-pointing arrow shape + fill | 2 |
| `.customBezier` | User-defined bezier path (premium) | variable |

### Metal Stencil Clipping
For non-rectangular cells, the renderer must clip the photo texture to the cell's `CGPath`:

1. Convert `CGPath` → `MTLBuffer` of vertices using `CGPathApply`
2. Render cell photo to an offscreen `MTLTexture`
3. Apply stencil: only keep pixels within the path boundary
4. Composite the stenciled texture onto the main canvas

Alternative (simpler, acceptable for v1): use `Core Image` masking via `CIBlendWithMask` — slower but avoids stencil buffer complexity. Profile both on iPhone 13 before deciding.

### Custom Bezier Editor (Premium)
A drawing canvas where the user traces a cell boundary using bezier handles:
- Add/remove anchor points with tap
- Drag handles to adjust curve
- Path must be closed (first and last point connected)
- Snap to canvas edges and center guides
- Output: `CGPath` stored in `CollageCell.customClipPath: Data` (serialized via `CGPath` archival)

---

## Checklist

### Polygon Layout Engine
- [ ] Extend `CollageLayoutEngine` with `polygonLayout(for:canvasSize:)` method
- [ ] Implement all 9 named polygon types listed above
- [ ] Each polygon path must be a closed `CGPath` with no gaps
- [ ] Paths must tile perfectly — no pixel gaps between adjacent cells
- [ ] Test visually: render each layout at 1080×1080 and inspect for seams

### Metal Renderer — Polygon Support
- [ ] Add stencil clipping support to `CollageRenderer`
- [ ] Cells with `clipPath == nil` use the existing rectangle path (no change)
- [ ] Cells with `clipPath != nil` are clipped to the path before compositing
- [ ] Smooth anti-aliasing at cell edges (use MSAA or Core Image soften post-pass)
- [ ] Performance target: still 60fps on iPhone 13 with a 5-cell polygon layout

### Polygon Template JSON
- [ ] Add `"shapeType"` field to template JSON schema: `"rectangle"` | `"diagonal_left"` | `"hexagon"` etc.
- [ ] Create 10 polygon template JSON files in `Resources/Templates/`
- [ ] Confirm all 10 parse correctly via unit test

### Grid Editor UI — Polygon Mode (UIKit)
- [ ] Add a **Shapes** segment to the layout picker `UICollectionView` in the Grid Editor bottom toolbar
- [ ] Shapes segment shows a horizontal scroll of polygon layout thumbnails
- [ ] Selecting a polygon layout replaces the current grid layout (with undo support)
- [ ] Cell shapes render correctly in both the preview canvas and the exported image

### Custom Bezier Editor (Premium Gate, UIKit)
- [ ] Create `Features/GridEditor/BezierEditorViewController.swift` (`UIViewController`)
- [ ] Accessible from the **Shapes** segment → **Custom** option (shown but gated for free users)
- [ ] Canvas: full-screen `UIView` with a `CAShapeLayer` overlay for the path, current collage dimmed underneath
- [ ] Anchor point controls: `UITapGestureRecognizer` to add, `UILongPressGestureRecognizer` to delete, `UIPanGestureRecognizer` on handles to curve — composed so they don't conflict
- [ ] Snap guides: center cross, canvas thirds (drawn into a `CAShapeLayer` guides overlay)
- [ ] **Done** → applies path to selected cell; **Cancel** → reverts
- [ ] Serialize final `CGPath` using `NSKeyedArchiver` and store in `CollageCell.customClipPathData: Data?`

### Template Parser — Polygon Support
- [ ] Update `TemplateService` to parse `shapeType` from JSON
- [ ] Map string values to `CellShape` enum cases
- [ ] Unknown `shapeType` values fall back to `.rectangle` without crashing

### Export
No new export logic needed — the Metal compositor already handles polygon cells via stencil clipping. The export path reuses Step 01's export sheet unchanged.

---

## Unit Tests — `CaroullageTests/Unit/CollageLayoutEngineTests.swift` (extend)
`CaroullageTests/Unit/TemplateParserTests.swift` (new file)

**Polygon layout tests (add to existing file):**
- [ ] `testDiagonalLeftProducesTwoCells()` — exactly 2 cells returned
- [ ] `testDiagonalCellPathsAreClosed()` — `CGPath.isEmpty` is false for both cells
- [ ] `testPolygonCellsDoNotOverlap()` — no pixel in canvas belongs to more than one cell
- [ ] `testHexagonGridProducesSevenCells()` — exactly 7 cells

**Template parser tests (new file):**
- [ ] `testValidRectangleTemplateParses()` — expected cell count + frame values
- [ ] `testValidPolygonTemplateParses()` — `shapeType` maps to correct `CellShape`
- [ ] `testMissingShapeTypeDefaultsToRectangle()` — no crash on missing field
- [ ] `testUnknownShapeTypeDefaultsToRectangle()` — `"shapeType": "banana"` → `.rectangle`
- [ ] `testMissingCanvasAspectRatioThrowsError()` — required field missing → throw
- [ ] `testInvalidFrameValuesClamped()` — frame values outside 0.0–1.0 → clamped, no crash
- [ ] `testPremiumFlagParsedCorrectly()` — `"isPremium": true` maps to `true`
- [ ] `testTemplateCellCountMatchesJSON()` — cell count in parsed model equals array length in JSON

Run: `Cmd+U` → all pass.

---

## Internal Alpha Build — Pillar 1 Complete

After Step 02, build a Pillar-1-complete alpha for internal review. This is **not** a TestFlight build (TestFlight + StoreKit + Featuring nomination all live in Step 06 / Deployment). Just a working internal build to verify gesture feel and export correctness.

- [ ] Bump version to `0.1.0 (1)` in Xcode
- [ ] Build with Debug scheme; install on team test devices via Xcode
- [ ] Walk-through review: focus on export quality, gesture feel, layout correctness, memory profile

---

## Done Criteria

- [ ] All 9 polygon layout types render correctly with no visible seams between cells
- [ ] Custom bezier editor creates and applies a user-drawn cell boundary
- [ ] Polygon cells export correctly — the stencil clipping matches what the preview shows
- [ ] All 12 unit tests (4 polygon + 8 parser) pass
- [ ] Template parser handles all invalid input gracefully — no crashes in any edge case
- [ ] Instruments: still < 200 MB memory with a 7-cell hexagon layout
