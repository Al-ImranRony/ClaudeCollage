# Editor Chrome and Collage Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the three shared editor-chrome components, fix the hard-pinned square canvas, and rebuild `GridEditorViewController` on the chrome with a tool rail, swap-in panels, and contextual tool groups.

**Architecture:** Three new UIKit components under `Caroullage/Core/DesignSystem/Editor/` — `EditorStage` (aspect-correct canvas host), `EditorToolRail` (base tools + insertable contextual group), `EditorPanel` (swap-in controls container). Geometry maths lives in a pure, window-free helper so it is unit-testable. The collage editor keeps its existing `GridEditorViewModel` untouched and only changes how controls are presented. `TextStyle` is added to the shared `TextRendering` draw path so canvas and export cannot disagree.

**Tech Stack:** Swift 6 (strict concurrency), UIKit, XCTest, XcodeGen, Xcode 26.5 / iOS 26.5 SDK.

**Spec:** `docs/superpowers/specs/2026-09-05-editor-redesign-collage-canvas-and-video-timeline-design.md`

---

## Before you start

The `.xcodeproj` is generated and gitignored. **Every task that adds a file must re-run `xcodegen generate` before building**, or the new file will not be in the target.

Set up your shell once:

```bash
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH="$DEVELOPER_DIR/usr/bin:$PATH"
cd "/Users/irony/Claude/Projects/ClaudeCollage"
```

Boot one simulator explicitly and reuse it for the whole plan. Letting `xcodebuild` pick a
device by name is what wedges the simulator with `Application failed preflight checks`:

```bash
xcrun simctl shutdown all
DEV=$(xcrun simctl list devices available | grep -E 'iPhone 17 \(' | head -1 | grep -oE '[0-9A-F-]{36}')
xcrun simctl boot "$DEV"; xcrun simctl bootstatus "$DEV" -b
echo "$DEV"   # keep this; every test command below uses it
```

`bootstatus` ending `Status=4294967295, isTerminal=YES ... Finished` is success, not an error.

**Never run two simulator jobs at once.** Do not start a build while a test run is going.

The standard test command used throughout, narrowed to one class:

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/<ClassName> 2>&1 | tail -25
```

**House rules this codebase enforces** — violating any of these will get the change rejected:

- Use `Theme.*` tokens and `Haptics.*`. Never `.systemBackground`, `.preferredFont`, `.tintColor`, or a hardcoded colour.
- `Theme.Color.*` are **computed** static vars (stored `UIColor` statics trip strict concurrency). Read them at use time.
- Never set `layer.cornerRadius` on a `UIButton` that has a `UIButton.Configuration` — the configuration owns its corner radius.
- Every new model field decodes with a fallback via `decodeIfPresent`, matching `TextOverlay.init(from:)`.

---

## File structure

| File | Responsibility |
|---|---|
| `Caroullage/Core/DesignSystem/Editor/EditorTool.swift` | The value types: `EditorTool`, `EditorRailContext`. No UIKit behaviour. |
| `Caroullage/Core/DesignSystem/Editor/EditorStageGeometry.swift` | Pure aspect-fit maths. No views, so it is testable without a window. |
| `Caroullage/Core/DesignSystem/Editor/EditorStage.swift` | Canvas host. Owns the replaceable aspect constraint. |
| `Caroullage/Core/DesignSystem/Editor/EditorToolRail.swift` | The bottom rail. Base tools plus an insertable contextual group. |
| `Caroullage/Core/DesignSystem/Editor/EditorPanel.swift` | Swap-in panel container with animated height. |
| `Caroullage/Core/Models/TextStyle.swift` | The tier-2 text presentation model. |
| `Caroullage/Core/Models/TextOverlay.swift` | *Modify* — gains `style`. |
| `Caroullage/Core/Rendering/TextRendering.swift` | *Modify* — draws `TextStyle`. |
| `Caroullage/Features/GridEditor/GridEditorViewController.swift` | *Modify* — rebuilt on the chrome. |
| `Caroullage/Features/GridEditor/Panels/GridEditorPanels.swift` | The Layout / Frame / Background panel content views, extracted so the VC does not grow. |
| `CaroullageTests/Unit/EditorChromeTests.swift` | Tests for the three components. |
| `CaroullageTests/Unit/TextStyleTests.swift` | Tests for the model and its rendering. |
| `CaroullageTests/Unit/EditorControlTrayTests.swift` | *Modify* — rewritten against the rail. |

---

## Task 1: `EditorTool` and `EditorRailContext` value types

**Files:**
- Create: `Caroullage/Core/DesignSystem/Editor/EditorTool.swift`
- Test: `CaroullageTests/Unit/EditorChromeTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CaroullageTests/Unit/EditorChromeTests.swift`:

```swift
//
//  EditorChromeTests.swift
//  CaroullageTests
//
//  The shared editor chrome: the value types, the aspect-fit maths, the rail's
//  contextual insertion, and the panel's present/dismiss contract.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class EditorChromeTests: XCTestCase {

    // MARK: - Value types

    func testAToolCarriesItsAccessibilityIdentifier() {
        let tool = EditorTool(
            id: "layout", title: "Layout",
            systemImage: "square.grid.2x2", accessibilityIdentifier: "layoutTool")

        XCTAssertEqual(tool.id, "layout")
        XCTAssertEqual(tool.accessibilityIdentifier, "layoutTool")
    }

    func testAContextCarriesItsChipAndTools() {
        let context = EditorRailContext(
            chipTitle: "Photo", chipSystemImage: "photo",
            tools: [EditorTool(id: "replace", title: "Replace",
                               systemImage: "arrow.left.arrow.right",
                               accessibilityIdentifier: "replacePhotoTool")])

        XCTAssertEqual(context.chipTitle, "Photo")
        XCTAssertEqual(context.tools.map(\.id), ["replace"])
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorChromeTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'EditorTool' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Caroullage/Core/DesignSystem/Editor/EditorTool.swift`:

```swift
//
//  EditorTool.swift
//  Caroullage
//
//  The value types behind `EditorToolRail`. Kept free of UIKit behaviour so the
//  editors can describe their tool sets declaratively and the rail stays a dumb
//  renderer of whatever it is handed.
//

import Foundation

/// One tool in an editor's bottom rail.
public struct EditorTool: Equatable, Identifiable, Sendable {
    public typealias ID = String

    public let id: ID
    public let title: String
    /// SF Symbol name.
    public let systemImage: String
    /// Preserved across the redesign so existing XCUITests keep matching.
    public let accessibilityIdentifier: String

    public init(id: ID, title: String, systemImage: String, accessibilityIdentifier: String) {
        self.id = id
        self.title = title
        self.systemImage = systemImage
        self.accessibilityIdentifier = accessibilityIdentifier
    }
}

/// A contextual tool group inserted ahead of the base tools when something on the
/// canvas is selected. The base tools are never removed — they scroll.
public struct EditorRailContext: Equatable, Sendable {
    public let chipTitle: String
    /// SF Symbol name shown in the dismissible chip.
    public let chipSystemImage: String
    public let tools: [EditorTool]

    public init(chipTitle: String, chipSystemImage: String, tools: [EditorTool]) {
        self.chipTitle = chipTitle
        self.chipSystemImage = chipSystemImage
        self.tools = tools
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 2 tests.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/DesignSystem/Editor/EditorTool.swift CaroullageTests/Unit/EditorChromeTests.swift
git commit -m "feat(editor): add EditorTool and EditorRailContext value types"
```

---

## Task 2: `EditorStageGeometry` — the aspect-fit maths

The bug in the collage editor is a constraint, but the *behaviour* worth testing is "what
rect does a document of this aspect get inside this space". Extracting it makes it testable
without a window and gives both editors one answer.

**Files:**
- Create: `Caroullage/Core/DesignSystem/Editor/EditorStageGeometry.swift`
- Test: `CaroullageTests/Unit/EditorChromeTests.swift:*` (append)

- [ ] **Step 1: Write the failing test**

Append inside `EditorChromeTests`:

```swift
    // MARK: - Stage geometry

    private let stageInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16)

    func testASquareDocumentIsWidthLimitedInATallSpace() {
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 1080, height: 1080),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.width, 370, accuracy: 0.5)
        XCTAssertEqual(rect.height, 370, accuracy: 0.5)
    }

    func testAStoryDocumentGrowsTallInsteadOfBeingSquashedIntoASquare() {
        // The regression this whole plan exists for. Usable space here is 370 x 665,
        // and 370 / (9/16) = 657.8, which still fits — so a story canvas is WIDTH
        // limited and 657.8pt tall, not capped at the old 370pt square.
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.width, 370, accuracy: 0.5)
        XCTAssertEqual(rect.height, 657.78, accuracy: 0.5)
        XCTAssertGreaterThan(rect.height, 370,
                             "A story canvas must be taller than the old square cap")
    }

    func testAVeryTallDocumentBecomesHeightLimited() {
        // Past 1:1.8 the height runs out first and the canvas narrows instead.
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 1000, height: 3000),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.height, 665, accuracy: 0.5)
        XCTAssertEqual(rect.width, 221.67, accuracy: 0.5)
    }

    func testALandscapeDocumentIsWidthLimited() {
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 1920, height: 1080),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.width, 370, accuracy: 0.5)
        XCTAssertEqual(rect.height, 208.13, accuracy: 0.5)
    }

    func testTheCanvasIsCentredInTheStage() {
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 1080, height: 1920),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.midX, 201, accuracy: 0.5)
        XCTAssertEqual(rect.midY, 340.5, accuracy: 0.5)
    }

    func testADegenerateCanvasSizeFallsBackToSquare() {
        // A malformed document must not produce a zero or NaN rect.
        let rect = EditorStageGeometry.canvasRect(
            canvasSize: CGSize(width: 0, height: 0),
            in: CGRect(x: 0, y: 0, width: 402, height: 681),
            insets: stageInsets)

        XCTAssertEqual(rect.width, 370, accuracy: 0.5)
        XCTAssertEqual(rect.height, 370, accuracy: 0.5)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorChromeTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'EditorStageGeometry' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Caroullage/Core/DesignSystem/Editor/EditorStageGeometry.swift`:

```swift
//
//  EditorStageGeometry.swift
//  Caroullage
//
//  The stage's aspect-fit maths, kept pure so it is testable without a window and
//  so both editors get the same answer for "how big is this document on screen".
//

import CoreGraphics
import UIKit

public enum EditorStageGeometry {

    /// The largest rect with `canvasSize`'s aspect ratio that fits inside `bounds`
    /// after `insets`, centred. A degenerate canvas size falls back to 1:1 rather
    /// than producing a zero or NaN rect.
    public static func canvasRect(
        canvasSize: CGSize,
        in bounds: CGRect,
        insets: UIEdgeInsets
    ) -> CGRect {
        let available = bounds.inset(by: insets)
        guard available.width > 0, available.height > 0 else { return .zero }

        let aspect: CGFloat
        if canvasSize.width > 0, canvasSize.height > 0 {
            aspect = canvasSize.width / canvasSize.height
        } else {
            aspect = 1
        }

        // Width-limited when the document is wider than the space it is given.
        var size = CGSize(width: available.width, height: available.width / aspect)
        if size.height > available.height {
            size = CGSize(width: available.height * aspect, height: available.height)
        }

        return CGRect(
            x: available.midX - size.width / 2,
            y: available.midY - size.height / 2,
            width: size.width,
            height: size.height
        )
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 8 tests.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/DesignSystem/Editor/EditorStageGeometry.swift CaroullageTests/Unit/EditorChromeTests.swift
git commit -m "feat(editor): add EditorStageGeometry aspect-fit maths"
```

---

## Task 3: `EditorStage`

**Files:**
- Create: `Caroullage/Core/DesignSystem/Editor/EditorStage.swift`
- Test: `CaroullageTests/Unit/EditorChromeTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `EditorChromeTests`:

```swift
    // MARK: - Stage view

    private func layOutStage(canvasSize: CGSize) -> (EditorStage, UIView) {
        let stage = EditorStage()
        let content = UIView()
        stage.setContent(content)
        stage.setCanvasAspect(canvasSize)
        stage.frame = CGRect(x: 0, y: 0, width: 402, height: 681)
        stage.layoutIfNeeded()
        return (stage, content)
    }

    func testTheStageSizesItsContentToTheDocumentAspect() {
        let (_, content) = layOutStage(canvasSize: CGSize(width: 1080, height: 1920))

        XCTAssertEqual(content.bounds.width / content.bounds.height, 1080.0 / 1920.0,
                       accuracy: 0.01, "Content must take the document's aspect, not a square")
        XCTAssertGreaterThan(content.bounds.height, 370,
                             "A story canvas must beat the old 370pt square cap")
    }

    func testChangingTheAspectRelaysOutTheContent() {
        let (stage, content) = layOutStage(canvasSize: CGSize(width: 1080, height: 1080))
        XCTAssertEqual(content.bounds.width / content.bounds.height, 1, accuracy: 0.01)

        stage.setCanvasAspect(CGSize(width: 1080, height: 1920))
        stage.layoutIfNeeded()

        XCTAssertEqual(content.bounds.width / content.bounds.height, 1080.0 / 1920.0,
                       accuracy: 0.01, "The aspect constraint must be replaced, not stacked")
    }

    func testReplacingContentRemovesThePreviousView() {
        let (stage, first) = layOutStage(canvasSize: CGSize(width: 1080, height: 1080))
        let second = UIView()
        stage.setContent(second)
        stage.layoutIfNeeded()

        XCTAssertNil(first.superview)
        XCTAssertEqual(second.superview, stage)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorChromeTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'EditorStage' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Caroullage/Core/DesignSystem/Editor/EditorStage.swift`:

```swift
//
//  EditorStage.swift
//  Caroullage
//
//  Hosts an editor's canvas and owns its geometry. The canvas takes the DOCUMENT's
//  aspect ratio through a stored, replaceable multiplier constraint — the grid
//  editor previously pinned it square, which letterboxed every 9:16 story collage
//  into 44% dead space.
//
//  The stage fills whatever space is left between the navigation bar and the panel
//  or rail beneath it, so opening a panel shrinks the canvas smoothly instead of
//  the canvas being a fixed size with a scrolling form under it.
//

import UIKit

@MainActor
public final class EditorStage: UIView {

    /// Minimum breathing room around the canvas.
    public var contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16) {
        didSet { setNeedsLayout() }
    }

    private var content: UIView?
    private var canvasSize = CGSize(width: 1, height: 1)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.background
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Installs the canvas view, replacing any previous one.
    public func setContent(_ view: UIView) {
        content?.removeFromSuperview()
        content = view
        // Frame-driven: `layoutSubviews` positions the single child from
        // `EditorStageGeometry`, so it must NOT be under Auto Layout as well.
        view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(view)
        setNeedsLayout()
    }

    /// Sets the document's aspect ratio. A degenerate size is normalised to 1:1 by
    /// `EditorStageGeometry`, so a malformed document cannot produce a zero canvas.
    public func setCanvasAspect(_ canvasSize: CGSize) {
        self.canvasSize = canvasSize
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let content else { return }

        // Frame maths must run with an identity transform — setting `.frame` under a
        // non-identity transform is undefined. The canvas applies its pinch zoom to
        // its own inner container, so this is normally already identity; saving and
        // restoring costs nothing and makes the invariant explicit. This mirrors
        // `CanvasView.layoutCellGeometry()`.
        let transform = content.transform
        content.transform = .identity
        content.frame = EditorStageGeometry.canvasRect(
            canvasSize: canvasSize, in: bounds, insets: contentInsets)
        content.transform = transform
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 11 tests.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/DesignSystem/Editor/EditorStage.swift CaroullageTests/Unit/EditorChromeTests.swift
git commit -m "feat(editor): add EditorStage with a replaceable aspect constraint"
```

---

## Task 4: `EditorToolRail`

**Files:**
- Create: `Caroullage/Core/DesignSystem/Editor/EditorToolRail.swift`
- Test: `CaroullageTests/Unit/EditorChromeTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `EditorChromeTests`:

```swift
    // MARK: - Tool rail

    private func makeBaseTools() -> [EditorTool] {
        [
            EditorTool(id: "layout", title: "Layout",
                       systemImage: "square.grid.2x2", accessibilityIdentifier: "layoutTool"),
            EditorTool(id: "frame", title: "Frame",
                       systemImage: "square.dashed", accessibilityIdentifier: "frameTool"),
            EditorTool(id: "background", title: "Background",
                       systemImage: "circle.lefthalf.filled", accessibilityIdentifier: "backgroundTool"),
        ]
    }

    private func makePhotoContext() -> EditorRailContext {
        EditorRailContext(
            chipTitle: "Photo", chipSystemImage: "photo",
            tools: [
                EditorTool(id: "replace", title: "Replace",
                           systemImage: "arrow.left.arrow.right", accessibilityIdentifier: "replacePhotoTool"),
                EditorTool(id: "adjust", title: "Adjust",
                           systemImage: "circle.lefthalf.filled", accessibilityIdentifier: "adjustPhotoTool"),
            ])
    }

    func testTheRailShowsItsBaseToolsInOrder() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())

        XCTAssertEqual(rail.visibleToolIdentifiers, ["layoutTool", "frameTool", "backgroundTool"])
    }

    func testAContextIsInsertedAheadOfTheBaseToolsWithoutRemovingThem() {
        // The whole point of the "A + C" decision: contextual tools are additive.
        // A user must never lose a document tool because they tapped a photo.
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())

        XCTAssertEqual(
            rail.visibleToolIdentifiers,
            ["replacePhotoTool", "adjustPhotoTool", "layoutTool", "frameTool", "backgroundTool"])
    }

    func testClearingTheContextRestoresTheBaseToolsExactly() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        rail.setContext(nil)

        XCTAssertEqual(rail.visibleToolIdentifiers, ["layoutTool", "frameTool", "backgroundTool"])
    }

    func testSwappingOneContextForAnotherDoesNotAccumulate() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        rail.setContext(EditorRailContext(
            chipTitle: "Text", chipSystemImage: "textformat",
            tools: [EditorTool(id: "edit", title: "Edit",
                               systemImage: "keyboard", accessibilityIdentifier: "editTextTool")]))

        XCTAssertEqual(rail.visibleToolIdentifiers,
                       ["editTextTool", "layoutTool", "frameTool", "backgroundTool"])
    }

    func testTappingAToolReportsItsIdentifier() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        var selected: EditorTool.ID?
        rail.onSelect = { selected = $0 }

        rail.simulateTap(toolID: "frame")

        XCTAssertEqual(selected, "frame")
    }

    func testDismissingTheChipReportsAndClearsTheContext() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        var dismissed = false
        rail.onDismissContext = { dismissed = true }

        rail.simulateChipDismiss()

        XCTAssertTrue(dismissed)
        XCTAssertEqual(rail.visibleToolIdentifiers, ["layoutTool", "frameTool", "backgroundTool"])
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorChromeTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'EditorToolRail' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Caroullage/Core/DesignSystem/Editor/EditorToolRail.swift`:

```swift
//
//  EditorToolRail.swift
//  Caroullage
//
//  The editors' bottom tool rail. It holds a base tool set and can INSERT a
//  contextual group ahead of it when something on the canvas is selected — the
//  base tools are never removed, they scroll. A rail that swapped its contents
//  wholesale would make users hunt for a control that moved.
//
//  The rail's background reaches the bottom screen edge while its content stays
//  inside the safe area, which is what keeps the old "no dead band" behaviour
//  without the full-height scroll view that behaviour was originally built around.
//

import UIKit

@MainActor
public final class EditorToolRail: UIView {

    public var onSelect: ((EditorTool.ID) -> Void)?
    public var onDismissContext: (() -> Void)?

    /// Content height above the safe-area inset.
    public static let contentHeight: CGFloat = 52

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var baseTools: [EditorTool] = []
    private var context: EditorRailContext?
    private var activeToolID: EditorTool.ID?

    /// The accessibility identifiers of every tool button currently in the rail,
    /// in leading-to-trailing order. The chip and the divider are not tools.
    public var visibleToolIdentifiers: [String] {
        stack.arrangedSubviews
            .compactMap { ($0 as? UIControl)?.accessibilityIdentifier }
            .filter { $0 != Self.chipIdentifier }
    }

    private static let chipIdentifier = "editorRailContextChip"

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupSubviews() {
        let separator = UIView()
        separator.backgroundColor = Theme.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        scrollView.showsHorizontalScrollIndicator = false
        // The rail reaches the screen edge, so the automatic behaviour would hand
        // the home-indicator inset straight back as content inset.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            // Content sits inside the safe area; the view's background does not.
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                                           constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                            constant: -Theme.Spacing.xs),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
    }

    // MARK: - Content

    public func setBaseTools(_ tools: [EditorTool]) {
        baseTools = tools
        rebuild()
    }

    /// Sets or clears the contextual group. Passing a new context replaces the old
    /// one rather than adding to it.
    public func setContext(_ context: EditorRailContext?) {
        self.context = context
        rebuild()
        if context != nil {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    public func setActiveTool(_ id: EditorTool.ID?) {
        activeToolID = id
        for case let button as ToolButton in stack.arrangedSubviews {
            button.setActive(button.toolID == id)
        }
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        if let context {
            stack.addArrangedSubview(makeChip(context))
            for tool in context.tools {
                stack.addArrangedSubview(makeButton(tool))
            }
            stack.addArrangedSubview(makeDivider())
        }
        for tool in baseTools {
            stack.addArrangedSubview(makeButton(tool))
        }
        setActiveTool(activeToolID)
    }

    // MARK: - Subview factories

    private func makeButton(_ tool: EditorTool) -> ToolButton {
        let button = ToolButton(tool: tool)
        button.accessibilityIdentifier = tool.accessibilityIdentifier
        button.accessibilityLabel = tool.title
        button.addAction(UIAction { [weak self] _ in
            Haptics.selectionChanged()
            self?.onSelect?(tool.id)
        }, for: .touchUpInside)
        return button
    }

    private func makeChip(_ context: EditorRailContext) -> UIControl {
        let chip = ContextChip(title: context.chipTitle, systemImage: context.chipSystemImage)
        chip.accessibilityIdentifier = Self.chipIdentifier
        chip.accessibilityLabel = "\(context.chipTitle) selected. Double tap to deselect."
        chip.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.setContext(nil)
            self?.onDismissContext?()
        }, for: .touchUpInside)
        return chip
    }

    private func makeDivider() -> UIView {
        let container = UIView()
        let line = UIView()
        line.backgroundColor = Theme.Color.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Theme.Spacing.sm),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.sm),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.sm),
        ])
        return container
    }

    // MARK: - Test seams

    /// Drives the same path a real tap does, without needing a window or a hit test.
    func simulateTap(toolID: EditorTool.ID) {
        guard let button = stack.arrangedSubviews
            .compactMap({ $0 as? ToolButton })
            .first(where: { $0.toolID == toolID }) else { return }
        button.sendActions(for: .touchUpInside)
    }

    func simulateChipDismiss() {
        guard let chip = stack.arrangedSubviews
            .compactMap({ $0 as? UIControl })
            .first(where: { $0.accessibilityIdentifier == Self.chipIdentifier }) else { return }
        chip.sendActions(for: .touchUpInside)
    }
}

// MARK: - Tool button

@MainActor
private final class ToolButton: UIControl {

    let toolID: EditorTool.ID
    private let icon = UIImageView()
    private let label = UILabel()

    init(tool: EditorTool) {
        self.toolID = tool.id
        super.init(frame: .zero)

        icon.image = UIImage(systemName: tool.systemImage)
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        label.text = tool.title
        label.font = Theme.Typography.tabLabel
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
        setActive(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Indigo marks *which thing is chosen*; ink is ordinary chrome.
    func setActive(_ isActive: Bool) {
        let colour = isActive ? Theme.Color.accent : Theme.Color.textSecondary
        icon.tintColor = colour
        label.textColor = colour
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}

// MARK: - Context chip

@MainActor
private final class ContextChip: UIControl {

    init(title: String, systemImage: String) {
        super.init(frame: .zero)

        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.tintColor = Theme.Color.accent

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.tabLabel
        label.textColor = Theme.Color.accent

        let close = UIImageView(image: UIImage(systemName: "xmark"))
        close.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        close.tintColor = Theme.Color.accent

        let stack = UIStackView(arrangedSubviews: [icon, label, close])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        backgroundColor = Theme.Color.accentSoft
        layer.cornerRadius = Theme.Radius.sm
        layer.cornerCurve = .continuous

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.xs),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 17 tests.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/DesignSystem/Editor/EditorToolRail.swift CaroullageTests/Unit/EditorChromeTests.swift
git commit -m "feat(editor): add EditorToolRail with additive contextual groups"
```

---

## Task 5: `EditorPanel`

**Files:**
- Create: `Caroullage/Core/DesignSystem/Editor/EditorPanel.swift`
- Test: `CaroullageTests/Unit/EditorChromeTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `EditorChromeTests`:

```swift
    // MARK: - Panel

    func testAFreshPanelIsNotPresenting() {
        let panel = EditorPanel()
        XCTAssertFalse(panel.isPresenting)
        XCTAssertTrue(panel.isHidden)
    }

    func testShowingAPanelInstallsTheContentAndTitle() {
        let panel = EditorPanel()
        let content = UIView()
        panel.show(content, title: "Layout", animated: false)

        XCTAssertTrue(panel.isPresenting)
        XCTAssertFalse(panel.isHidden)
        XCTAssertEqual(panel.currentTitle, "Layout")
        XCTAssertNotNil(content.superview)
    }

    func testShowingASecondPanelReplacesTheFirstContent() {
        let panel = EditorPanel()
        let first = UIView()
        let second = UIView()
        panel.show(first, title: "Layout", animated: false)
        panel.show(second, title: "Frame", animated: false)

        XCTAssertNil(first.superview, "The previous panel content must be torn down")
        XCTAssertNotNil(second.superview)
        XCTAssertEqual(panel.currentTitle, "Frame")
    }

    func testHidingTearsDownTheContent() {
        let panel = EditorPanel()
        let content = UIView()
        panel.show(content, title: "Layout", animated: false)
        panel.hide(animated: false)

        XCTAssertFalse(panel.isPresenting)
        XCTAssertTrue(panel.isHidden)
        XCTAssertNil(content.superview)
    }

    func testTheCloseControlReportsThrough() {
        let panel = EditorPanel()
        panel.show(UIView(), title: "Layout", animated: false)
        var closed = false
        panel.onClose = { closed = true }

        panel.simulateClose()

        XCTAssertTrue(closed)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorChromeTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'EditorPanel' in scope`.

- [ ] **Step 3: Write the implementation**

Create `Caroullage/Core/DesignSystem/Editor/EditorPanel.swift`:

```swift
//
//  EditorPanel.swift
//  Caroullage
//
//  The swap-in controls container that sits between the stage and the rail. One
//  tool's controls at a time — the collage editor previously stacked every control
//  it had into one long scroll, which reads as a settings form rather than an editor.
//
//  Hiding sets `isHidden` rather than removing the view, so the stage's height
//  animation has something stable to animate against.
//

import UIKit

@MainActor
public final class EditorPanel: UIView {

    public var onClose: (() -> Void)?
    public private(set) var isPresenting = false

    /// Exposed for tests and for the VC's own bookkeeping.
    public private(set) var currentTitle: String?

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let contentContainer = UIView()
    private var content: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surfaceRaised
        isHidden = true
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupSubviews() {
        let separator = UIView()
        separator.backgroundColor = Theme.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        titleLabel.font = Theme.Typography.tabLabel
        titleLabel.textColor = Theme.Color.textSecondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Theme.Color.textSecondary
        closeButton.accessibilityIdentifier = "editorPanelCloseButton"
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onClose?()
        }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.xs),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.md),

            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.md),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                                                  constant: Theme.Spacing.xs),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor,
                                                     constant: -Theme.Spacing.xs),
        ])
    }

    // MARK: - Presentation

    public func show(_ view: UIView, title: String, animated: Bool) {
        content?.removeFromSuperview()
        content = view

        titleLabel.text = title.uppercased()
        currentTitle = title

        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        isPresenting = true
        setVisible(true, animated: animated)
    }

    public func hide(animated: Bool) {
        guard isPresenting else { return }
        isPresenting = false
        currentTitle = nil
        setVisible(false, animated: animated) { [weak self] in
            self?.content?.removeFromSuperview()
            self?.content = nil
        }
    }

    private func setVisible(_ visible: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        guard animated, !Theme.Motion.isReduced else {
            isHidden = !visible
            alpha = visible ? 1 : 0
            completion?()
            return
        }
        if visible { isHidden = false; alpha = 0 }
        UIView.animate(withDuration: Theme.Motion.quick) {
            self.alpha = visible ? 1 : 0
        } completion: { _ in
            self.isHidden = !visible
            completion?()
        }
    }

    // MARK: - Test seam

    func simulateClose() {
        closeButton.sendActions(for: .touchUpInside)
    }
}
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 22 tests.

- [ ] **Step 5: Commit**

```bash
git add Caroullage/Core/DesignSystem/Editor/EditorPanel.swift CaroullageTests/Unit/EditorChromeTests.swift
git commit -m "feat(editor): add EditorPanel swap-in controls container"
```

---

## Task 6: `TextStyle` model

**Files:**
- Create: `Caroullage/Core/Models/TextStyle.swift`
- Modify: `Caroullage/Core/Models/TextOverlay.swift`
- Test: `CaroullageTests/Unit/TextStyleTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CaroullageTests/Unit/TextStyleTests.swift`:

```swift
//
//  TextStyleTests.swift
//  CaroullageTests
//
//  The tier-2 text presentation model. The decode tests matter more than they look:
//  every already-saved project must keep rendering exactly as it does today, which
//  means a snapshot written before this field existed has to decode to `.plain`.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class TextStyleTests: XCTestCase {

    func testTheDefaultStyleIsPlain() {
        XCTAssertEqual(TextStyle().kind, .plain)
    }

    func testEveryKindIsRoundTripped() throws {
        for kind in TextStyle.Kind.allCases {
            let style = TextStyle(kind: kind, colorHex: "#112233", width: 9)
            let data = try JSONEncoder().encode(style)
            let decoded = try JSONDecoder().decode(TextStyle.self, from: data)
            XCTAssertEqual(decoded, style, "\(kind) must survive a round trip")
        }
    }

    func testAnUnknownKindFallsBackToPlainRatherThanThrowing() throws {
        // A project written by a future build must still open in this one.
        let json = Data(#"{"kind":"hologram","colorHex":"#000000","width":6}"#.utf8)
        let decoded = try JSONDecoder().decode(TextStyle.self, from: json)
        XCTAssertEqual(decoded.kind, .plain)
    }

    func testAnEmptyObjectDecodesToTheDefaults() throws {
        let decoded = try JSONDecoder().decode(TextStyle.self, from: Data("{}".utf8))
        XCTAssertEqual(decoded, TextStyle())
    }

    func testAnOverlaySavedBeforeStylesExistedDecodesToPlain() throws {
        // The exact shape a pre-change snapshot has: no `style` key at all.
        let json = Data(#"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertEqual(overlay.style, TextStyle())
        XCTAssertEqual(overlay.text, "hi")
    }

    func testAnOverlayRoundTripsItsStyle() throws {
        var overlay = TextOverlay(text: "hi")
        overlay.style = TextStyle(kind: .stroke, colorHex: "#FF0000", width: 4)

        let data = try JSONEncoder().encode(overlay)
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

        XCTAssertEqual(decoded.style, overlay.style)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/TextStyleTests 2>&1 | tail -25
```

Expected: FAIL — `cannot find 'TextStyle' in scope`.

- [ ] **Step 3: Write the model**

Create `Caroullage/Core/Models/TextStyle.swift`:

```swift
//
//  TextStyle.swift
//  Caroullage
//
//  How a text overlay is PRESENTED, as distinct from what it says and how it is
//  typeset. White text over bright footage is unreadable, and bright footage is
//  most of what people shoot — these are the treatments that fix that, shipped as
//  one-tap presets rather than five loose sliders.
//
//  `width` is in POINTS ON THE REFERENCE CANVAS, the same convention as
//  `TextOverlay.fontSize`, so a renderer scales it by the same `fontScale`.
//

import Foundation

public struct TextStyle: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// No treatment.
        case plain
        /// Soft drop shadow.
        case shadow
        /// Outline around the glyphs.
        case stroke
        /// Solid rounded rectangle behind the whole text block.
        case pill
        /// Solid rectangle hugging the text, marker-pen style.
        case highlight
        /// Coloured outer glow.
        case glow
    }

    public var kind: Kind
    /// Stroke, pill, highlight or glow colour. Ignored by `.plain`.
    public var colorHex: String
    /// Stroke width, glow radius, or pill corner inset — reference-canvas points.
    public var width: Double

    public init(kind: Kind = .plain, colorHex: String = "#000000", width: Double = 6) {
        self.kind = kind
        self.colorHex = colorHex
        self.width = max(0, width)
    }

    private enum CodingKeys: String, CodingKey { case kind, colorHex, width }

    /// Defensive, matching `TextOverlay.init(from:)`: an unknown kind from a future
    /// build decodes to `.plain` rather than throwing and losing the whole project.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TextStyle()
        let raw = try c.decodeIfPresent(String.self, forKey: .kind)
        self.kind = raw.flatMap(Kind.init(rawValue:)) ?? fallback.kind
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? fallback.colorHex
        self.width = max(0, try c.decodeIfPresent(Double.self, forKey: .width) ?? fallback.width)
    }
}
```

- [ ] **Step 4: Add `style` to `TextOverlay`**

In `Caroullage/Core/Models/TextOverlay.swift`, make four edits.

Add the stored property after `isUnderlined`:

```swift
    public var isUnderlined: Bool
    /// How the text is presented over its background. See `TextStyle`.
    public var style: TextStyle
```

Add the initialiser parameter after `isUnderlined: Bool = false,`:

```swift
        isUnderlined: Bool = false,
        style: TextStyle = TextStyle(),
```

Assign it in the initialiser body after `self.isUnderlined = isUnderlined`:

```swift
        self.isUnderlined = isUnderlined
        self.style = style
```

Add `style` to `CodingKeys`:

```swift
    private enum CodingKeys: String, CodingKey {
        case id, text, fontName, fontSize, colorHex, alignmentRaw
        case letterSpacing, lineHeight, opacity, isBold, isItalic, isUnderlined
        case style
        case frameX, frameY, frameWidth, frameHeight
    }
```

And decode it defensively in `init(from:)`, after the `isUnderlined` line:

```swift
        self.isUnderlined = try c.decodeIfPresent(Bool.self, forKey: .isUnderlined) ?? fallback.isUnderlined
        self.style = try c.decodeIfPresent(TextStyle.self, forKey: .style) ?? fallback.style
```

- [ ] **Step 5: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 6 tests.

- [ ] **Step 6: Run the whole unit suite to prove nothing else regressed**

`TextOverlay` is persisted, exported and undone — a new field touches more than its own test.

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageTests 2>&1 | tail -25
```

Expected: PASS. If `LocalizationTests` fails, that is a pre-existing string-catalog sync
issue and not caused by this change — confirm by stashing and re-running.

- [ ] **Step 7: Commit**

```bash
git add Caroullage/Core/Models/TextStyle.swift Caroullage/Core/Models/TextOverlay.swift CaroullageTests/Unit/TextStyleTests.swift
git commit -m "feat(text): add TextStyle presentation model to TextOverlay"
```

---

## Task 7: Render `TextStyle` in `TextRendering`

One draw path serves the live canvas, the photo export and the video export, so a style
drawn here cannot disagree between preview and file.

**Files:**
- Modify: `Caroullage/Core/Rendering/TextRendering.swift:50-100`
- Test: `CaroullageTests/Unit/TextStyleTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `TextStyleTests`:

```swift
    // MARK: - Rendering

    private func attributes(for style: TextStyle) -> [NSAttributedString.Key: Any] {
        var overlay = TextOverlay(text: "Hello", fontSize: 64)
        overlay.style = style
        let string = TextRendering.attributedString(for: overlay, fontScale: 1)
        return string.attributes(at: 0, effectiveRange: nil)
    }

    func testPlainAddsNoStrokeAndNoShadow() {
        let attrs = attributes(for: TextStyle(kind: .plain))
        XCTAssertNil(attrs[.strokeWidth])
        XCTAssertNil(attrs[.shadow])
    }

    func testStrokeUsesANegativeWidthSoTheFillIsKept() {
        // A POSITIVE .strokeWidth draws the outline ONLY and hollows the glyph out.
        // Negative means "stroke and fill", which is what a caption outline needs.
        let attrs = attributes(for: TextStyle(kind: .stroke, colorHex: "#FF0000", width: 4))
        let width = try? XCTUnwrap(attrs[.strokeWidth] as? CGFloat)
        XCTAssertNotNil(width)
        XCTAssertLessThan(width ?? 0, 0)
        XCTAssertNotNil(attrs[.strokeColor])
    }

    func testShadowAndGlowBothInstallAShadow() {
        XCTAssertNotNil(attributes(for: TextStyle(kind: .shadow))[.shadow])
        XCTAssertNotNil(attributes(for: TextStyle(kind: .glow))[.shadow])
    }

    func testStrokeWidthScalesWithTheCanvas() {
        // Reference-canvas points must scale like fontSize does, or a thumbnail
        // gets a stroke as thick as the full-resolution export.
        var overlay = TextOverlay(text: "Hello", fontSize: 64)
        overlay.style = TextStyle(kind: .stroke, colorHex: "#000000", width: 8)

        let full = TextRendering.attributedString(for: overlay, fontScale: 1)
            .attributes(at: 0, effectiveRange: nil)[.strokeWidth] as? CGFloat
        let half = TextRendering.attributedString(for: overlay, fontScale: 0.5)
            .attributes(at: 0, effectiveRange: nil)[.strokeWidth] as? CGFloat

        XCTAssertNotNil(full)
        XCTAssertNotNil(half)
        XCTAssertEqual(abs(half ?? 0), abs(full ?? 0) / 2, accuracy: 0.01)
    }

    func testDrawingAPillStyleProducesDifferentPixelsThanPlain() {
        // The pill background is painted in `draw`, not in the attributes, so this
        // is the only way to prove it lands.
        func render(_ style: TextStyle) -> Data? {
            var overlay = TextOverlay(text: "Hello",
                                      colorHex: "#000000",
                                      frame: CGRect(x: 0, y: 0, width: 1, height: 1))
            overlay.style = style
            let size = CGSize(width: 200, height: 100)
            let renderer = UIGraphicsImageRenderer(size: size)
            return renderer.pngData { ctx in
                TextRendering.draw(overlay,
                                   in: CGRect(origin: .zero, size: size),
                                   fontScale: 0.2,
                                   context: ctx.cgContext)
            }
        }

        let plain = render(TextStyle(kind: .plain))
        let pill = render(TextStyle(kind: .pill, colorHex: "#FFCC00", width: 6))

        XCTAssertNotNil(plain)
        XCTAssertNotNil(pill)
        XCTAssertNotEqual(plain, pill, "A pill background must actually be painted")
    }
```

Add `import UIKit` to the top of the file alongside the existing imports.

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/TextStyleTests 2>&1 | tail -30
```

Expected: FAIL — `testStrokeUsesANegativeWidthSoTheFillIsKept` fails on a nil `strokeWidth`.

- [ ] **Step 3: Add the style attributes**

In `TextRendering.attributedString(for:fontScale:)`, after the `if overlay.isUnderlined`
block and before `return`, insert:

```swift
        applyStyle(overlay.style, fontScale: fontScale, to: &attributes)
        return NSAttributedString(string: overlay.text, attributes: attributes)
    }

    /// Applies the presentation treatment. Kept separate from typesetting so the
    /// pill / highlight kinds — which paint behind the text rather than changing it
    /// — can be no-ops here and handled in `draw`.
    private static func applyStyle(
        _ style: TextStyle,
        fontScale: CGFloat,
        to attributes: inout [NSAttributedString.Key: Any]
    ) {
        let colour = UIColor(hex: style.colorHex)
        let width = CGFloat(style.width) * fontScale

        switch style.kind {
        case .plain, .pill, .highlight:
            break

        case .stroke:
            // NEGATIVE means stroke AND fill. A positive value hollows the glyph out.
            attributes[.strokeColor] = colour
            attributes[.strokeWidth] = -width

        case .shadow:
            let shadow = NSShadow()
            shadow.shadowColor = colour.withAlphaComponent(0.55)
            shadow.shadowBlurRadius = max(1, width)
            shadow.shadowOffset = CGSize(width: 0, height: max(1, width * 0.35))
            attributes[.shadow] = shadow

        case .glow:
            let shadow = NSShadow()
            shadow.shadowColor = colour
            shadow.shadowBlurRadius = max(1, width * 1.6)
            shadow.shadowOffset = .zero
            attributes[.shadow] = shadow
        }
    }
```

Delete the now-duplicated `return NSAttributedString(...)` line that previously ended the
method, so the method ends at the inserted `return`.

- [ ] **Step 4: Paint the pill and highlight backgrounds**

In `TextRendering.draw(_:in:fontScale:context:)`, insert the background paint after
`cg.clip(to: absoluteFrame)` and before `attributed.draw(...)`:

```swift
        cg.saveGState()
        cg.clip(to: absoluteFrame)
        drawBackground(for: overlay.style,
                       textRect: CGRect(x: absoluteFrame.minX, y: originY,
                                        width: absoluteFrame.width, height: drawnHeight),
                       fontScale: fontScale,
                       context: cg)
        attributed.draw(with: CGRect(x: absoluteFrame.minX, y: originY,
                                     width: absoluteFrame.width, height: drawnHeight),
                        options: [.usesLineFragmentOrigin, .usesFontLeading],
                        context: nil)
        cg.restoreGState()
```

Then add the helper below `draw`:

```swift
    /// Paints the solid backgrounds that sit BEHIND the glyphs. `.pill` is a rounded
    /// rectangle around the whole block; `.highlight` hugs the text with square-ish
    /// corners, marker-pen style.
    private static func drawBackground(
        for style: TextStyle,
        textRect: CGRect,
        fontScale: CGFloat,
        context cg: CGContext
    ) {
        let inset = CGFloat(style.width) * fontScale
        let rect: CGRect
        let radius: CGFloat

        switch style.kind {
        case .pill:
            rect = textRect.insetBy(dx: -inset, dy: -inset * 0.6)
            radius = min(rect.height / 2, inset * 2)
        case .highlight:
            rect = textRect.insetBy(dx: -inset * 0.5, dy: -inset * 0.25)
            radius = inset * 0.3
        case .plain, .shadow, .stroke, .glow:
            return
        }

        guard rect.width > 0, rect.height > 0 else { return }
        cg.saveGState()
        cg.setFillColor(UIColor(hex: style.colorHex).cgColor)
        UIBezierPath(roundedRect: rect, cornerRadius: max(0, radius)).fill()
        cg.restoreGState()
    }
```

- [ ] **Step 5: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 11 tests.

- [ ] **Step 6: Run the rendering suites to prove preview still equals export**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageTests 2>&1 | tail -25
```

Expected: PASS. `.plain` is the default, so every existing text assertion must be unchanged.

- [ ] **Step 7: Commit**

```bash
git add Caroullage/Core/Rendering/TextRendering.swift CaroullageTests/Unit/TextStyleTests.swift
git commit -m "feat(text): render TextStyle treatments in the shared draw path"
```

---

## Task 8: The collage editor adopts `EditorStage` — the aspect fix

This is the smallest change with the largest visible effect. Do it on its own, before the
rail, so a regression here is unambiguous.

**Files:**
- Modify: `Caroullage/Features/GridEditor/GridEditorViewController.swift:178-305`
- Test: `CaroullageTests/Unit/EditorControlTrayTests.swift` (rewrite)

- [ ] **Step 1: Write the failing test**

Replace the whole body of `CaroullageTests/Unit/EditorControlTrayTests.swift` with:

```swift
//
//  EditorControlTrayTests.swift
//  CaroullageTests
//
//  Originally a Step 06 guard: the editor's control tray was pinned to the safe
//  area, leaving a ~34pt dead band under the last row of controls.
//
//  The 2026-09-05 editor redesign replaced the full-height scrolling tray with an
//  `EditorToolRail`, so the original assertions — which reached for "the first
//  UIScrollView child of the root view" — no longer describe the screen. The INTENT
//  survives unchanged and is what these tests now pin: the rail's background reaches
//  the physical bottom edge, its controls stay inside the safe area, and the canvas
//  takes the document's aspect ratio rather than a hardcoded square.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class EditorControlTrayTests: XCTestCase {

    /// Windows are held for the length of the test: `additionalSafeAreaInsets` only
    /// reaches `view.safeAreaInsets` once the view is in a window, and without that
    /// the assertions below pass against any layout at all.
    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(
        bottomInset: CGFloat,
        canvasSize: CGSize = CGSize(width: 1080, height: 1080)
    ) -> GridEditorViewController {
        let editor = GridEditorViewController(
            viewModel: GridEditorViewModel(canvasSize: canvasSize))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        // Stands in for the home indicator, which an off-device window lacks.
        editor.additionalSafeAreaInsets = UIEdgeInsets(
            top: 0, left: 0, bottom: bottomInset, right: 0)
        window.layoutIfNeeded()
        return editor
    }

    private func rail(in editor: GridEditorViewController) -> EditorToolRail? {
        editor.view.subviews.compactMap { $0 as? EditorToolRail }.first
    }

    func testTheHarnessActuallyAppliesTheInset() {
        // Guards every test below: if the fake home indicator does not reach the
        // view, the assertions are vacuous and pass against any layout.
        let editor = makeEditor(bottomInset: 34)
        XCTAssertEqual(editor.view.safeAreaInsets.bottom, 34, accuracy: 0.5)
    }

    func testTheRailBackgroundReachesTheBottomEdge() throws {
        let editor = makeEditor(bottomInset: 34)
        let rail = try XCTUnwrap(rail(in: editor))

        XCTAssertEqual(
            rail.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5,
            "The rail runs to the screen edge rather than stopping above it")
    }

    func testTheRailStillFillsTheScreenWithoutAHomeIndicator() throws {
        let editor = makeEditor(bottomInset: 0)
        let rail = try XCTUnwrap(rail(in: editor))

        XCTAssertEqual(rail.frame.maxY, editor.view.bounds.maxY, accuracy: 0.5)
    }

    func testTheRailsControlsStayInsideTheSafeArea() throws {
        // The background reaching the edge must not drag the buttons under the
        // home indicator with it.
        let editor = makeEditor(bottomInset: 34)
        let rail = try XCTUnwrap(rail(in: editor))
        let scroll = try XCTUnwrap(rail.subviews.compactMap { $0 as? UIScrollView }.first)

        XCTAssertLessThanOrEqual(
            scroll.convert(scroll.bounds, to: editor.view).maxY,
            editor.view.bounds.maxY - 34 + 0.5,
            "Rail controls must not sit under the home indicator")
    }

    // MARK: - The canvas aspect fix

    func testASquareDocumentGetsASquareCanvas() throws {
        let editor = makeEditor(bottomInset: 34, canvasSize: CGSize(width: 1080, height: 1080))
        let stage = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorStage }.first)
        let canvas = try XCTUnwrap(stage.subviews.first)

        XCTAssertEqual(canvas.bounds.width / canvas.bounds.height, 1, accuracy: 0.02)
    }

    func testAStoryDocumentIsNoLongerSquashedIntoASquare() throws {
        // The regression this redesign exists for. The canvas view was pinned
        // `height == width`, so a 9:16 collage drew at 208x370 inside a 370x370 box.
        let editor = makeEditor(bottomInset: 34, canvasSize: CGSize(width: 1080, height: 1920))
        let stage = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorStage }.first)
        let canvas = try XCTUnwrap(stage.subviews.first)

        XCTAssertEqual(canvas.bounds.width / canvas.bounds.height, 1080.0 / 1920.0,
                       accuracy: 0.02, "The canvas must take the document's aspect")
        XCTAssertGreaterThan(canvas.bounds.height, 420,
                             "A story canvas must be far taller than the old 370pt square")
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/EditorControlTrayTests 2>&1 | tail -25
```

Expected: FAIL — no `EditorStage` or `EditorToolRail` in the editor's view hierarchy yet.

- [ ] **Step 3: Replace the editor's layout**

In `GridEditorViewController`, replace the stored properties at lines 22–34 that describe
the old tray with the chrome, keeping `canvasView`:

```swift
    private let canvasView = CanvasView()
    private let stage = EditorStage()
    private let toolRail = EditorToolRail()
    private let toolPanel = EditorPanel()
```

Keep `layoutModeControl`, `layoutPicker`, `shapePicker`, `customShapeButton`,
`backgroundPicker`, `borderSlider` and `cornerSlider` — Task 9 re-homes them into panels.
Delete `customShapeRow` and `layoutSection`, which only existed to hide rows in the old
stack.

Then replace `setupLayout()` entirely:

```swift
    private func setupLayout() {
        view.backgroundColor = Theme.Color.background

        canvasView.backgroundColor = Theme.Color.cellWell
        canvasView.layer.cornerRadius = Theme.Radius.md
        canvasView.layer.cornerCurve = .continuous
        canvasView.clipsToBounds = true

        stage.setContent(canvasView)
        stage.setCanvasAspect(viewModel.canvasSize)

        stage.translatesAutoresizingMaskIntoConstraints = false
        toolPanel.translatesAutoresizingMaskIntoConstraints = false
        toolRail.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stage)
        view.addSubview(toolPanel)
        view.addSubview(toolRail)

        NSLayoutConstraint.activate([
            stage.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            stage.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            stage.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            stage.bottomAnchor.constraint(equalTo: toolPanel.topAnchor),

            toolPanel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolPanel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            toolPanel.bottomAnchor.constraint(equalTo: toolRail.topAnchor),

            toolRail.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            toolRail.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            // The REAL bottom, not the safe-area bottom: the tab bar is hidden while
            // an editor is pushed, so pinning to the safe area leaves an empty band
            // under the rail that nothing can ever fill.
            toolRail.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
```

Delete `sectionLabel(_:)`, `labelledSlider(_:slider:systemImage:)`,
`makeAddOverlayBar()`, `makeAddButton(...)` and `makeGenerativeBackgroundRow()` only after
Task 9 has re-homed their contents — for this task, leave them in place, unused. The
compiler will warn; that is expected and resolved in the next task.

- [ ] **Step 4: Keep the aspect in sync with the document**

In `bindViewModel()`, inside the existing `viewModel.onGeometryChange` handler (add the
handler if it is not already assigned), add:

```swift
        viewModel.onGeometryChange = { [weak self] in
            guard let self else { return }
            self.stage.setCanvasAspect(self.viewModel.canvasSize)
            self.reconfigureCanvas()
        }
```

- [ ] **Step 5: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 6 tests.

- [ ] **Step 6: Confirm the change on a real screen, not just in a test**

A green suite does not prove the binary you are looking at was rebuilt. Build to an
explicit derived-data path and screenshot it.

```bash
xcodebuild build -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -derivedDataPath /tmp/caroullage-dd 2>&1 | tail -5
APP=/tmp/caroullage-dd/Build/Products/Debug-iphonesimulator/Caroullage.app
stat -f "%Sm" -t "%m-%d %H:%M:%S" "$APP/Caroullage"    # must be from THIS build
xcrun simctl install "$DEV" "$APP"
xcrun simctl launch "$DEV" com.devron.caroullage.dev
```

Open a 9:16 Story template and screenshot:

```bash
xcrun simctl io "$DEV" screenshot /tmp/story-canvas.png
```

Expected: the collage fills the width of the stage and runs nearly the full height above
the rail. If it is still a centred square, the constraint change did not take.

- [ ] **Step 7: Commit**

```bash
git add Caroullage/Features/GridEditor/GridEditorViewController.swift CaroullageTests/Unit/EditorControlTrayTests.swift
git commit -m "fix(editor): size the collage canvas to the document aspect, not a square"
```

---

## Task 9: The collage editor's base rail and panels

**Files:**
- Create: `Caroullage/Features/GridEditor/Panels/GridEditorPanels.swift`
- Modify: `Caroullage/Features/GridEditor/GridEditorViewController.swift`
- Test: `CaroullageTests/Unit/GridEditorRailTests.swift`

- [ ] **Step 1: Write the failing test**

Create `CaroullageTests/Unit/GridEditorRailTests.swift`:

```swift
//
//  GridEditorRailTests.swift
//  CaroullageTests
//
//  The collage editor's tool rail: which tools it offers, which panel each opens,
//  and the one document type that must not be offered a layout choice at all.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class GridEditorRailTests: XCTestCase {

    private var windows: [UIWindow] = []

    override func tearDown() async throws {
        await MainActor.run { windows.removeAll() }
        try await super.tearDown()
    }

    private func makeEditor(
        layout: CollageLayout = .grid(.fourSquare)
    ) -> GridEditorViewController {
        let viewModel = GridEditorViewModel(
            canvasSize: CGSize(width: 1080, height: 1080),
            state: GridEditorState(layout: layout))
        let editor = GridEditorViewController(viewModel: viewModel)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        windows.append(window)
        window.layoutIfNeeded()
        return editor
    }

    private func rail(in editor: GridEditorViewController) throws -> EditorToolRail {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
    }

    private func panel(in editor: GridEditorViewController) throws -> EditorPanel {
        try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorPanel }.first)
    }

    func testTheBaseRailOffersTheFiveDocumentTools() throws {
        let rail = try rail(in: makeEditor())

        XCTAssertEqual(rail.visibleToolIdentifiers,
                       ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testATemplateDocumentIsNotOfferedALayoutChoice() throws {
        // A template defines its own geometry; offering a layout picker would claim
        // a selection the document does not have.
        let template = TemplateLayout(
            templateID: "test.single",
            name: "Test",
            aspectRatio: "1:1",
            cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))])
        let rail = try rail(in: makeEditor(layout: .template(template)))

        XCTAssertFalse(rail.visibleToolIdentifiers.contains("layoutTool"))
    }

    func testNoPanelIsOpenOnLaunch() throws {
        // The canvas gets the whole stage until the user asks for a tool.
        XCTAssertFalse(try panel(in: makeEditor()).isPresenting)
    }

    func testTappingLayoutOpensTheLayoutPanel() throws {
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "layout")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Layout")
    }

    func testTappingFrameOpensTheFramePanelWithBothSliders() throws {
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "frame")

        let panel = try panel(in: editor)
        XCTAssertEqual(panel.currentTitle, "Frame")
        let sliders = panel.recursiveSubviews.compactMap { $0 as? UISlider }
        XCTAssertEqual(sliders.count, 2, "Border and Corners")
    }

    func testTappingTheSameToolTwiceClosesThePanel() throws {
        // Toggling gives the canvas its full height back without hunting for the ✕.
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "layout")
        rail.simulateTap(toolID: "layout")

        XCTAssertFalse(try panel(in: editor).isPresenting)
    }

    func testSwitchingToolsSwapsThePanelWithoutClosingIt() throws {
        let editor = makeEditor()
        let rail = try rail(in: editor)
        rail.simulateTap(toolID: "layout")
        rail.simulateTap(toolID: "background")

        let panel = try panel(in: editor)
        XCTAssertTrue(panel.isPresenting)
        XCTAssertEqual(panel.currentTitle, "Background")
    }

    func testTheLayoutPickerLivesInsideTheLayoutPanel() throws {
        // PolygonQAUITests reaches for this collection view by identifier; it must
        // still exist, just scoped to the panel now.
        let editor = makeEditor()
        try rail(in: editor).simulateTap(toolID: "layout")

        let picker = try panel(in: editor).recursiveSubviews
            .first { $0.accessibilityIdentifier == "layoutPicker" }
        XCTAssertNotNil(picker)
    }
}

extension UIView {
    /// Every descendant, depth first. Test-only convenience.
    var recursiveSubviews: [UIView] {
        subviews + subviews.flatMap(\.recursiveSubviews)
    }
}
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/GridEditorRailTests 2>&1 | tail -25
```

Expected: FAIL — the rail has no tools yet, so `visibleToolIdentifiers` is empty.

- [ ] **Step 3: Extract the panel content views**

Create `Caroullage/Features/GridEditor/Panels/GridEditorPanels.swift`:

```swift
//
//  GridEditorPanels.swift
//  Caroullage
//
//  The content views for the collage editor's three document panels. They live
//  here rather than in the view controller because the controller was already the
//  largest file in the feature, and each of these is a self-contained group of
//  controls with one job.
//

import UIKit

/// `Grid / Shapes / Custom` over the matching picker.
@MainActor
final class LayoutPanelView: UIView {

    private let modeControl: UISegmentedControl
    private let layoutPicker: LayoutPickerView
    private let shapePicker: ShapePickerView
    private let customButton: UIButton
    private let stack: UIStackView

    init(
        modeControl: UISegmentedControl,
        layoutPicker: LayoutPickerView,
        shapePicker: ShapePickerView,
        customButton: UIButton
    ) {
        self.modeControl = modeControl
        self.layoutPicker = layoutPicker
        self.shapePicker = shapePicker
        self.customButton = customButton
        self.stack = UIStackView(arrangedSubviews: [modeControl, layoutPicker, shapePicker, customButton])
        super.init(frame: .zero)

        stack.axis = .vertical
        stack.spacing = Theme.Spacing.xs
        stack.isLayoutMarginsRelativeArrangement = true
        stack.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Shows the picker that matches the selected mode. The pickers keep their own
    /// selection state, so this only toggles visibility.
    func showPolygonControls(_ isPolygon: Bool) {
        layoutPicker.isHidden = isPolygon
        shapePicker.isHidden = !isPolygon
        customButton.isHidden = !isPolygon
    }
}

/// The Border and Corners sliders.
@MainActor
final class FramePanelView: UIView {

    init(borderSlider: UISlider, cornerSlider: UISlider) {
        super.init(frame: .zero)

        let rows = UIStackView(arrangedSubviews: [
            Self.row(title: "Border", systemImage: "square.dashed", slider: borderSlider),
            Self.row(title: "Corners", systemImage: "rotate.left", slider: cornerSlider),
        ])
        rows.axis = .vertical
        rows.spacing = Theme.Spacing.xs
        rows.isLayoutMarginsRelativeArrangement = true
        rows.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        rows.translatesAutoresizingMaskIntoConstraints = false
        addSubview(rows)

        NSLayoutConstraint.activate([
            rows.topAnchor.constraint(equalTo: topAnchor),
            rows.bottomAnchor.constraint(equalTo: bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private static func row(title: String, systemImage: String, slider: UISlider) -> UIView {
        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.tintColor = Theme.Color.textSecondary
        icon.contentMode = .scaleAspectFit

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.caption
        label.textColor = Theme.Color.textSecondary

        let row = UIStackView(arrangedSubviews: [icon, label, slider])
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 18),
            label.widthAnchor.constraint(equalToConstant: 62),
        ])
        return row
    }
}

/// The background swatches, with the AI generative entry as the trailing chip.
///
/// `generativeButton` is OPTIONAL on purpose. Image Playground needs Apple
/// Intelligence hardware, and where it cannot run the control must be absent
/// entirely rather than present-but-disabled — offering a premium feature the
/// device can never run would be false advertising. `MagicEraserUITests` pins this.
@MainActor
final class BackgroundPanelView: UIView {

    init(picker: BackgroundPickerView, generativeButton: UIButton?) {
        super.init(frame: .zero)

        let arranged: [UIView] = [picker] + (generativeButton.map { [$0] } ?? [])
        let row = UIStackView(arrangedSubviews: arranged)
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: 0, bottom: 0, right: Theme.Spacing.md)
        row.translatesAutoresizingMaskIntoConstraints = false
        addSubview(row)

        var constraints = [
            row.topAnchor.constraint(equalTo: topAnchor),
            row.bottomAnchor.constraint(equalTo: bottomAnchor),
            row.leadingAnchor.constraint(equalTo: leadingAnchor),
            row.trailingAnchor.constraint(equalTo: trailingAnchor),
        ]
        if let generativeButton {
            constraints.append(generativeButton.widthAnchor.constraint(equalToConstant: 44))
        }
        NSLayoutConstraint.activate(constraints)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}
```

- [ ] **Step 4: Wire the rail in the view controller**

Add to `GridEditorViewController`, and call `setupRail()` from `viewDidLoad()` after
`setupLayout()`:

```swift
    // MARK: - Tool rail

    private var openToolID: EditorTool.ID?

    private func setupRail() {
        var tools: [EditorTool] = []
        // A template defines its own geometry — offering a layout picker would claim
        // a selection the document does not have.
        if viewModel.state.layout.offersLayoutAlternatives {
            tools.append(EditorTool(id: "layout", title: "Layout",
                                    systemImage: "square.grid.2x2",
                                    accessibilityIdentifier: "layoutTool"))
        }
        tools.append(contentsOf: [
            EditorTool(id: "frame", title: "Frame",
                       systemImage: "square.dashed", accessibilityIdentifier: "frameTool"),
            EditorTool(id: "background", title: "Background",
                       systemImage: "circle.lefthalf.filled",
                       accessibilityIdentifier: "backgroundTool"),
            // Identifiers preserved from the old pill buttons so existing UI tests
            // keep matching.
            EditorTool(id: "text", title: "Text",
                       systemImage: "textformat", accessibilityIdentifier: "addTextButton"),
            EditorTool(id: "sticker", title: "Sticker",
                       systemImage: "face.smiling", accessibilityIdentifier: "addStickerButton"),
        ])
        toolRail.setBaseTools(tools)

        toolRail.onSelect = { [weak self] in self?.toolTapped($0) }
        toolRail.onDismissContext = { [weak self] in self?.clearSelection() }
        toolPanel.onClose = { [weak self] in self?.closePanel() }
    }

    private func toolTapped(_ id: EditorTool.ID) {
        // Tapping the open tool again closes it and gives the canvas its height back.
        guard id != openToolID else { return closePanel() }

        switch id {
        case "layout":      openPanel(makeLayoutPanel(), title: "Layout", id: id)
        case "frame":       openPanel(makeFramePanel(), title: "Frame", id: id)
        case "background":  openPanel(makeBackgroundPanel(), title: "Background", id: id)
        case "text":        addTextTapped()
        case "sticker":     addStickerTapped()
        default:            break
        }
    }

    private func openPanel(_ content: UIView, title: String, id: EditorTool.ID) {
        openToolID = id
        toolRail.setActiveTool(id)
        toolPanel.show(content, title: title, animated: true)
        animateStageResize()
    }

    private func closePanel() {
        openToolID = nil
        toolRail.setActiveTool(nil)
        toolPanel.hide(animated: true)
        animateStageResize()
    }

    /// The stage and the panel share one animation block so the canvas grows and
    /// shrinks smoothly instead of jumping a frame after the panel moves.
    private func animateStageResize() {
        guard !Theme.Motion.isReduced else { return view.layoutIfNeeded() }
        UIView.animate(
            withDuration: Theme.Motion.standard,
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction]
        ) {
            self.view.layoutIfNeeded()
        }
    }

    // MARK: - Panel factories

    private func makeLayoutPanel() -> UIView {
        layoutModeControl.selectedSegmentIndex = viewModel.state.layout.isPolygon ? 1 : 0
        let panel = LayoutPanelView(
            modeControl: layoutModeControl,
            layoutPicker: layoutPicker,
            shapePicker: shapePicker,
            customButton: customShapeButton)
        panel.showPolygonControls(viewModel.state.layout.isPolygon)
        layoutPanel = panel
        return panel
    }

    private func makeFramePanel() -> UIView {
        borderSlider.value = Float(normalizedBorder)
        cornerSlider.value = Float(normalizedCorner)
        return FramePanelView(borderSlider: borderSlider, cornerSlider: cornerSlider)
    }

    private func makeBackgroundPanel() -> UIView {
        BackgroundPanelView(picker: backgroundPicker,
                            generativeButton: makeGenerativeBackgroundButton())
    }
```

Add the stored property alongside the others so `layoutModeChanged()` can reach the panel:

```swift
    private weak var layoutPanel: LayoutPanelView?
```

Change `layoutModeChanged()` so it drives the panel instead of the deleted rows — replace
every reference to `shapePicker.isHidden`, `layoutPicker.isHidden` and `customShapeRow`
in that method with a single call:

```swift
        layoutPanel?.showPolygonControls(isPolygon)
```

Extract the AI generative entry from the old row into a chip:

```swift
    /// The AI generative-background entry, as the trailing chip of the Background
    /// panel rather than a row of its own.
    ///
    /// Returns `nil` where Image Playground cannot run — the old row hid itself for
    /// the same reason, and `MagicEraserUITests` asserts the button is ABSENT, not
    /// merely disabled. Do not simplify this to always return a button.
    private func makeGenerativeBackgroundButton() -> UIButton? {
        guard aiService.generativeBackgroundsAvailable else { return nil }

        var config = UIButton.Configuration.tinted()
        config.image = UIImage(systemName: "sparkles")
        config.cornerStyle = .capsule   // never set layer.cornerRadius on a configured button
        config.baseBackgroundColor = Theme.Color.accent
        config.baseForegroundColor = Theme.Color.accent
        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            Haptics.tap()
            self?.presentGenerativeBackground()
        })
        button.accessibilityIdentifier = "generateBackgroundButton"
        button.accessibilityLabel = "Generate background"
        return button
    }
```

Now delete the dead code the redesign replaced: `sectionLabel(_:)`,
`labelledSlider(_:slider:systemImage:)`, `makeAddOverlayBar()`, `makeAddButton(...)` and
`makeGenerativeBackgroundRow()`.

- [ ] **Step 5: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 8 tests.

- [ ] **Step 6: Run the full unit suite**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageTests 2>&1 | tail -25
```

Expected: PASS, including the rewritten `EditorControlTrayTests`.

- [ ] **Step 7: Commit**

```bash
git add Caroullage/Features/GridEditor CaroullageTests/Unit/GridEditorRailTests.swift
git commit -m "feat(editor): move the collage editor's controls into rail panels"
```

---

## Task 10: Contextual tool groups

**Files:**
- Modify: `Caroullage/Features/GridEditor/GridEditorViewController.swift`
- Test: `CaroullageTests/Unit/GridEditorRailTests.swift` (append)

- [ ] **Step 1: Write the failing test**

Append inside `GridEditorRailTests`:

```swift
    // MARK: - Contextual groups

    func testSelectingACellInsertsThePhotoToolsAheadOfTheDocumentTools() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["replacePhotoTool", "adjustPhotoTool", "liftSubjectAction", "magicEraserAction",
             "clearCellTool",
             "layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"],
            "Document tools must survive a selection — they scroll, they do not vanish")
    }

    func testDeselectingRestoresTheBaseRail() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)
        editor.selectCellForTesting(nil)

        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testDismissingTheChipDeselectsTheCell() throws {
        let editor = makeEditor()
        editor.selectCellForTesting(0)
        try rail(in: editor).simulateChipDismiss()

        XCTAssertNil(editor.selectedCellIndexForTesting)
    }

    func testSelectingATextOverlayInsertsTheTextTools() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)

        let identifiers = try rail(in: editor).visibleToolIdentifiers
        XCTAssertEqual(Array(identifiers.prefix(4)),
                       ["editTextTool", "styleTextTool", "duplicateTextTool", "deleteTextTool"])
    }

    func testDeletingATextOverlayRemovesItAndClearsTheSelection() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "deleteText")

        XCTAssertNil(editor.viewModelForTesting.textOverlay(id: id))
        XCTAssertEqual(
            try rail(in: editor).visibleToolIdentifiers,
            ["layoutTool", "frameTool", "backgroundTool", "addTextButton", "addStickerButton"])
    }

    func testDeletingATextOverlayIsUndoable() throws {
        // It rides `commit`, so it must land on the undo stack like every other edit.
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "deleteText")
        editor.viewModelForTesting.undo()

        XCTAssertNotNil(editor.viewModelForTesting.textOverlay(id: id))
    }

    func testTheTextStylePanelOffersEveryPreset() throws {
        let editor = makeEditor()
        let id = editor.addTextOverlayForTesting()
        editor.selectTextOverlayForTesting(id)
        try rail(in: editor).simulateTap(toolID: "styleText")

        let buttons = try panel(in: editor).recursiveSubviews
            .compactMap { $0 as? UIControl }
            .filter { ($0.accessibilityIdentifier ?? "").hasPrefix("textStyle_") }
        XCTAssertEqual(buttons.count, TextStyle.Kind.allCases.count)
    }
```

- [ ] **Step 2: Run the test to verify it fails**

```bash
xcodegen generate && xcodebuild test -project Caroullage.xcodeproj \
  -scheme "Caroullage (Dev)" -destination "id=$DEV" \
  -only-testing:CaroullageTests/GridEditorRailTests 2>&1 | tail -25
```

Expected: FAIL — `value of type 'GridEditorViewController' has no member 'selectCellForTesting'`.

- [ ] **Step 3: Add the contextual groups and the test seams**

Add to `GridEditorViewController`:

```swift
    // MARK: - Selection context

    private var selectedCellIndex: Int?
    private var selectedTextID: UUID?

    private static let photoTools: [EditorTool] = [
        EditorTool(id: "replace", title: "Replace", systemImage: "arrow.left.arrow.right",
                   accessibilityIdentifier: "replacePhotoTool"),
        EditorTool(id: "adjust", title: "Adjust", systemImage: "circle.lefthalf.filled",
                   accessibilityIdentifier: "adjustPhotoTool"),
        // Identifiers preserved from the retired action sheet.
        EditorTool(id: "lift", title: "Lift", systemImage: "person.and.background.dotted",
                   accessibilityIdentifier: "liftSubjectAction"),
        EditorTool(id: "erase", title: "Erase", systemImage: "eraser",
                   accessibilityIdentifier: "magicEraserAction"),
        EditorTool(id: "clear", title: "Clear", systemImage: "trash",
                   accessibilityIdentifier: "clearCellTool"),
    ]

    private static let textTools: [EditorTool] = [
        EditorTool(id: "editText", title: "Edit", systemImage: "keyboard",
                   accessibilityIdentifier: "editTextTool"),
        EditorTool(id: "styleText", title: "Style", systemImage: "textformat",
                   accessibilityIdentifier: "styleTextTool"),
        EditorTool(id: "duplicateText", title: "Duplicate", systemImage: "plus.square.on.square",
                   accessibilityIdentifier: "duplicateTextTool"),
        EditorTool(id: "deleteText", title: "Delete", systemImage: "trash",
                   accessibilityIdentifier: "deleteTextTool"),
    ]

    private func selectCell(_ index: Int?) {
        selectedCellIndex = index
        selectedTextID = nil
        canvasView.setSelectedCell(index)

        guard index != nil else { return clearContext() }
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Photo", chipSystemImage: "photo", tools: Self.photoTools))
    }

    private func selectTextOverlay(_ id: UUID?) {
        selectedTextID = id
        selectedCellIndex = nil
        canvasView.setSelectedCell(nil)

        guard id != nil else { return clearContext() }
        Haptics.selectionChanged()
        toolRail.setContext(EditorRailContext(
            chipTitle: "Text", chipSystemImage: "textformat", tools: Self.textTools))
    }

    private func clearSelection() {
        selectedCellIndex = nil
        selectedTextID = nil
        canvasView.setSelectedCell(nil)
        clearContext()
    }

    private func clearContext() {
        toolRail.setContext(nil)
        closePanel()
    }
```

Extend `toolTapped(_:)` with the contextual cases, before `default`:

```swift
        case "replace":
            selectedCellIndex.map { presentPhotoPicker(for: $0) }
        case "adjust":
            selectedCellIndex.map { presentFilterPanel(for: $0) }
        case "lift":
            selectedCellIndex.map { liftSubject(fromCellAt: $0) }
        case "erase":
            selectedCellIndex.map { presentMagicEraser(forCellAt: $0) }
        case "clear":
            if let index = selectedCellIndex {
                viewModel.clearCell(at: index)
                clearSelection()
            }
        case "editText":
            selectedTextID.map { presentTextStyleSheet(for: $0) }
        case "styleText":
            if let id = selectedTextID {
                openPanel(makeTextStylePanel(for: id), title: "Text", id: "styleText")
            }
        case "duplicateText":
            selectedTextID.map { duplicateTextOverlay($0) }
        case "deleteText":
            if let id = selectedTextID {
                viewModel.removeTextOverlay(id: id)
                clearSelection()
            }
```

`GridEditorViewModel` has no `removeTextOverlay` yet — only `removeSticker`. Add it
directly beneath `removeSticker(id:)` in `GridEditorViewModel.swift`, mirroring it exactly
so the deletion rides undo/redo and autosave the same way:

```swift
    /// Removes a text overlay (the Delete tool). Undoable.
    public func removeTextOverlay(id: UUID) {
        guard state.textOverlays.contains(where: { $0.id == id }) else { return }
        commit { $0.textOverlays.removeAll { $0.id == id } }
    }
```

Replace `canvasTapped(_:)`'s call to `presentCellActions(for:)` with `selectCell(index)`,
and delete `presentCellActions(for:)` entirely — the action sheet is retired.

Point the canvas's text-tap callback at the new selection in `bindViewModel()`:

```swift
        canvasView.onTextTapped = { [weak self] in self?.selectTextOverlay($0) }
```

Add the style panel and the duplicate action:

```swift
    /// The tier-2 presets as one tappable row. Tapping one applies it immediately —
    /// the canvas is visible behind the panel, so the preview IS the confirmation.
    private func makeTextStylePanel(for id: UUID) -> UIView {
        let row = UIStackView()
        row.axis = .horizontal
        row.spacing = Theme.Spacing.xs
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)

        for kind in TextStyle.Kind.allCases {
            let button = UIButton(type: .system)
            button.setTitle("Aa", for: .normal)
            button.titleLabel?.font = Theme.Typography.headline
            button.accessibilityIdentifier = "textStyle_\(kind.rawValue)"
            button.accessibilityLabel = kind.rawValue.capitalized
            button.addAction(UIAction { [weak self] _ in
                guard let self, var overlay = self.viewModel.textOverlay(id: id) else { return }
                overlay.style = TextStyle(
                    kind: kind,
                    colorHex: self.onLightBackground ? "#FFFFFF" : "#000000",
                    width: 6)
                self.viewModel.previewTextOverlay(overlay)
                self.viewModel.commitInteractiveChange()
                Haptics.selectionChanged()
            }, for: .touchUpInside)
            row.addArrangedSubview(button)
        }
        return row
    }

    private func duplicateTextOverlay(_ id: UUID) {
        guard var overlay = viewModel.textOverlay(id: id) else { return }
        overlay.id = UUID()
        overlay.frame = overlay.frame.offsetBy(dx: 0.03, dy: 0.03)
        let newID = viewModel.addTextOverlay(overlay)
        selectTextOverlay(newID)
        Haptics.tap()
    }
```

Finally add the test seams at the bottom of the class:

```swift
    // MARK: - Test seams

    var selectedCellIndexForTesting: Int? { selectedCellIndex }

    var viewModelForTesting: GridEditorViewModel { viewModel }

    func selectCellForTesting(_ index: Int?) { selectCell(index) }

    func selectTextOverlayForTesting(_ id: UUID?) { selectTextOverlay(id) }

    func addTextOverlayForTesting() -> UUID {
        viewModel.addTextOverlay(TextOverlay(
            text: "Test", frame: CGRect(x: 0.1, y: 0.4, width: 0.8, height: 0.15)))
    }
```

- [ ] **Step 4: Run the test to verify it passes**

Same command as Step 2. Expected: PASS, 15 tests.

- [ ] **Step 5: Run the full unit suite**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageTests 2>&1 | tail -25
```

Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add Caroullage/Features/GridEditor CaroullageTests/Unit/GridEditorRailTests.swift
git commit -m "feat(editor): replace the cell action sheet with contextual rail groups"
```

---

## Task 11: Update the UI tests the redesign moved

Four assertions reach for controls that are no longer always on screen. These are real
behaviour changes, so the tests change with them.

**Files:**
- Modify: `CaroullageUITests/UI/GridEditorFlowUITests.swift:35-36`
- Modify: `CaroullageUITests/UI/PolygonQAUITests.swift:55,85`
- Modify: `CaroullageUITests/UI/MagicEraserUITests.swift:48`

- [ ] **Step 1: Run the UI suite to see exactly what fails**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageUITests 2>&1 | tail -40
```

Expected: failures in `GridEditorFlowUITests`, `PolygonQAUITests`, `MagicEraserUITests`.
Note the exact test names — do not guess.

> If the runner reports `Application failed preflight checks` or `Busy`, the simulator is
> wedged. Run `xcrun simctl shutdown all`, re-boot `$DEV` with `bootstatus`, and retry.
> **Do not `erase all`** — it resets Photos authorization and breaks `ExportSaveUITests`.

- [ ] **Step 2: Point the layout / background assertions at the rail, and open Frame for the sliders**

In `CaroullageUITests/UI/GridEditorFlowUITests.swift`, replace lines 35–36:

```swift
        // The layout picker and sliders exist and are interactive.
        XCTAssertTrue(app.staticTexts["Layout"].exists)
        XCTAssertTrue(app.staticTexts["Background"].exists)
```

with:

```swift
        // The redesign moved these from always-visible section labels to rail tools.
        XCTAssertTrue(app.buttons["layoutTool"].exists, "Layout tool is in the rail")
        XCTAssertTrue(app.buttons["backgroundTool"].exists, "Background tool is in the rail")
```

Further down, the same test reaches for `app.sliders`. Border and Corners now live in the
Frame panel, so open it first. Immediately before the `let sliders = app.sliders` line, insert:

```swift
        // Border and Corners moved into the Frame panel.
        app.buttons["frameTool"].tap()
```

- [ ] **Step 3: Open the Layout panel once, early, in the polygon sweep**

`PolygonQAUITests.testPolygonEditorQASweep` drives the `Grid` / `Shapes` segmented control,
which now lives inside the Layout panel along with both pickers. Opening the panel once
after the editor pushes is the whole fix — the panel stays open for the rest of the sweep,
so the later `layoutPicker` assertions at lines 55 and 85 work unchanged.

After the `attach(app, "01_editor_grid_default")` line and before `let gridSeg = ...`, insert:

```swift
        // Grid/Shapes and both pickers now live in the Layout panel.
        app.buttons["layoutTool"].tap()
```

Change nothing else in this file. In particular **leave line 55 as it is** — it asserts the
grid picker is hidden in *Shapes mode*, which is still exactly the right assertion.

- [ ] **Step 4: Open the Background panel before asserting the AI chip is absent**

`MagicEraserUITests.testGenerativeBackgroundIsHiddenWhereItCannotRun` asserts the button is
**absent entirely, not present-but-disabled** — offering a premium feature the device can
never run would be false advertising. That rule does not change; only where the control
lives does. Open the panel first, then keep the same assertion:

```swift
        let app = openEditor()
        app.buttons["backgroundTool"].tap()
        XCTAssertFalse(app.buttons["generateBackgroundButton"].exists,
                       "Generate Background must not appear where it cannot run")
```

This is the test that will catch it if `makeGenerativeBackgroundButton()` was simplified to
always return a button. If it fails here, fix the factory, not the test.

- [ ] **Step 5: Run the UI suite to verify it passes**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" -only-testing:CaroullageUITests 2>&1 | tail -30
```

Expected: PASS.

> `ExportSaveUITests` can fail with "Photos prompt was not dismissed" if the simulator's
> Photos authorization was reset. That flake is unrelated to this change — see the project
> notes. Re-run it alone on a non-erased simulator to confirm.

- [ ] **Step 6: Run everything**

```bash
xcodebuild test -project Caroullage.xcodeproj -scheme "Caroullage (Dev)" \
  -destination "id=$DEV" 2>&1 | tail -30
```

Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add CaroullageUITests
git commit -m "test(ui): follow the editor controls into the rail and panels"
```

---

## Done when

- A 9:16 Story collage fills the stage instead of drawing at 208 × 370pt inside a square.
- The collage editor's bottom is a five-tool rail with swap-in panels, not one long scroll.
- Selecting a photo or a text zone inserts contextual tools without hiding the document tools.
- The cell `UIAlertController` is gone.
- `TextStyle` renders identically on canvas and in export, defaulting to `.plain` so every
  saved project is unchanged.
- The full test suite passes.

## One deliberate reduction against the spec

Spec §2.3 describes the text panel as carrying sub-tabs `Font / Style / Colour / Space`
that map onto `TextStyleSheet`'s sections, with the full sheet kept as a **More** route.

This plan builds the **Style** tab only — the tier-2 preset row — and routes the other
three through the `Edit` tool, which opens the existing `TextStyleSheet` unchanged. The
capability is all reachable; the inline sub-tabs for font, colour and spacing are not built.

The reason is sequencing, not scope-cutting: `TextStyleSheet` is a SwiftUI `Form` and
porting its pickers and sliders into a 140pt UIKit panel is a self-contained piece of work
that would double the size of Task 10 while adding nothing the video editor needs. It
belongs in its own follow-up alongside Plan 2's text panel, where the same sub-tabs are
built once for both editors. **Raise this with the spec owner before starting Task 10** if
the inline sub-tabs are wanted in this pass.

Plan 2 (video editor, timeline, timed text) is written against the components this plan
lands, so their real APIs — not predicted ones — are what it builds on.
