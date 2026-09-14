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
                       accuracy: 0.01, "Changing the aspect must re-lay-out the content")
    }

    func testReplacingContentRemovesThePreviousView() {
        let (stage, first) = layOutStage(canvasSize: CGSize(width: 1080, height: 1080))
        let second = UIView()
        stage.setContent(second)
        stage.layoutIfNeeded()

        XCTAssertNil(first.superview)
        XCTAssertEqual(second.superview, stage)
    }

    func testChangingContentInsetsRelaysOutTheContent() {
        let (stage, content) = layOutStage(canvasSize: CGSize(width: 1080, height: 1080))
        let before = content.bounds

        stage.contentInsets = UIEdgeInsets(top: 40, left: 60, bottom: 40, right: 60)
        stage.layoutIfNeeded()

        XCTAssertLessThan(content.bounds.width, before.width,
                          "Larger insets must shrink the content rect")
        XCTAssertLessThan(content.bounds.height, before.height,
                          "Larger insets must shrink the content rect")
    }

    func testANonIdentityTransformSurvivesLayout() {
        // Matches testAStoryDocumentGrowsTallInsteadOfBeingSquashedIntoASquare's
        // expected rect for this same canvas/stage size: 370 x 657.78.
        let (stage, content) = layOutStage(canvasSize: CGSize(width: 1080, height: 1920))
        let transform = CGAffineTransform(scaleX: 1.5, y: 1.5)
        content.transform = transform

        stage.setNeedsLayout()
        stage.layoutIfNeeded()

        XCTAssertEqual(content.transform, transform,
                       "The transform guard must restore the content's own transform")
        // A uniform scale divides both dimensions equally, so checking only the
        // aspect ratio would still pass even if the guard were deleted and the
        // frame were assigned under the live 1.5x transform. Assert the absolute
        // size to actually catch that: without the guard this comes out scaled
        // down to ~246.7 x ~438.5 instead.
        XCTAssertEqual(content.bounds.width, 370, accuracy: 0.5,
                       "Bounds must be the untransformed aspect-fit width")
        XCTAssertEqual(content.bounds.height, 657.78, accuracy: 0.5,
                       "Bounds must be the untransformed aspect-fit height")
    }

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

    func testAToolButtonResolvesToARealHitTarget() {
        // Regression test for a zero-height ToolButton: its inner icon/label stack
        // was pinned only by centerX/centerY, and a UIStackView with
        // alignment = .center never stretches a cross-axis arranged subview, so
        // the button had no source for its own height. It still drew fine
        // (clipsToBounds is off), but hitTest at the exact point the icon draws
        // resolved to the parent stack view, not the button — the button was
        // untappable in a real window even though every prior test passed
        // (simulateTap drives touchUpInside directly and never hit-tests).
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 402, height: EditorToolRail.contentHeight)
        rail.setBaseTools(makeBaseTools())
        rail.layoutIfNeeded()

        guard let button = rail.toolButton(for: "frame") else {
            return XCTFail("Expected a tool button for the \"frame\" tool")
        }

        XCTAssertGreaterThan(button.bounds.height, 0,
                             "ToolButton must derive a real height from its content")

        let centre = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: rail)
        let hit = rail.hitTest(centre, with: nil)

        XCTAssertTrue(hit?.isDescendant(of: button) ?? false,
                     "Hit-testing the button's visual centre must reach the button itself, " +
                     "not a parent stack view")
    }

    func testTheBaseToolsDivideTheRailsWidthEqually() {
        // Five tools bunched at the leading edge with dead space after them is
        // what the rail used to draw. With no context inserted the tools are
        // equal columns across the whole strip — a tab bar's rule.
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 402, height: EditorToolRail.contentHeight)
        rail.setBaseTools(makeBaseTools())
        rail.layoutIfNeeded()

        let buttons = ["layout", "frame", "background"].compactMap { rail.toolButton(for: $0) }
        XCTAssertEqual(buttons.count, 3)
        let widths = buttons.map(\.bounds.width)
        XCTAssertEqual(widths[0], widths[1], accuracy: 0.5)
        XCTAssertEqual(widths[1], widths[2], accuracy: 0.5)

        // The three columns together span the strip's content width, so the
        // middle tool sits on the rail's centre line.
        let middle = buttons[1].convert(CGPoint(x: buttons[1].bounds.midX, y: 0), to: rail)
        XCTAssertEqual(middle.x, rail.bounds.midX, accuracy: 0.5,
                       "the middle of an odd tool set must sit on the rail's centre")
    }

    func testAContextReturnsTheToolsToTheirNaturalWidths() {
        // Once a context is inserted the strip overflows and scrolls; a chip and
        // a divider given a tool's width each would be the wrong symmetry.
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 402, height: EditorToolRail.contentHeight)
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        rail.layoutIfNeeded()

        let equalColumn = (402 - 2 * 16) / 5.0
        let frame = rail.toolButton(for: "frame")!
        XCTAssertLessThan(frame.bounds.width, equalColumn,
                          "a scrolling strip must not stretch its tools into columns")
    }

    func testAWideRailKeepsAContextGroupPackedRatherThanSpread() {
        // iPad: the whole context fits, so the old `.equalSpacing` spread chip,
        // tools and divider across the width with ~50pt gaps. The group must
        // stay packed at the leading edge with its 4pt gap.
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 1180, height: EditorToolRail.contentHeight)
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        rail.layoutIfNeeded()

        let chip = rail.contextChipForLayout()!
        let replace = rail.toolButton(for: "replace")!
        let chipEnd = chip.convert(CGPoint(x: chip.bounds.maxX, y: 0), to: rail).x
        let toolStart = replace.convert(CGPoint(x: 0, y: 0), to: rail).x
        XCTAssertEqual(toolStart - chipEnd, 4, accuracy: 0.5,
                       "the chip sits beside its tools, not across the rail from them")
    }

    func testTheEmphasisPlaysOncePerSelectionAndNotOnARebuild() {
        // The owner's complaint was an effect that never stopped. `UIImageView`
        // has no getter for running effects, so the button counts its selection
        // moments: one per real selection, none for a rebuild that re-asserts
        // a selection the tool already had, none for re-selecting the active tool.
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 402, height: EditorToolRail.contentHeight)
        rail.setBaseTools(makeBaseTools())
        rail.layoutIfNeeded()

        rail.setActiveTool("frame")
        XCTAssertEqual(rail.toolButton(for: "frame")?.emphasisPlayCount, 1)

        rail.setActiveTool("frame")
        XCTAssertEqual(rail.toolButton(for: "frame")?.emphasisPlayCount, 1,
                       "re-asserting the active tool must not replay it")

        // A context change rebuilds every button; the new Frame button shows the
        // existing selection without playing it again.
        rail.setContext(makePhotoContext())
        XCTAssertEqual(rail.activeToolID, "frame")
        XCTAssertEqual(rail.toolButton(for: "frame")?.emphasisPlayCount, 0,
                       "a rebuilt button shows the selection; it does not celebrate it")

        rail.setActiveTool(nil)
        rail.setActiveTool("frame")
        XCTAssertEqual(rail.toolButton(for: "frame")?.emphasisPlayCount, 1)
    }

    func testTheActiveToolReadsAsSelectedToVoiceOver() {
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setActiveTool("frame")

        XCTAssertTrue(rail.toolButton(for: "frame")!.accessibilityTraits.contains(.selected))
        XCTAssertFalse(rail.toolButton(for: "layout")!.accessibilityTraits.contains(.selected))
    }

    func testSwappingContextClearsAStaleActiveHighlight() {
        // Regression test: setContext never touched activeToolID and rebuild()
        // unconditionally reapplied it, so an active tool from the old context
        // could keep lighting up after a swap — including on an unrelated tool
        // in the new context that happens to reuse the same identifier.
        let rail = EditorToolRail()
        rail.setBaseTools(makeBaseTools())
        rail.setContext(makePhotoContext())
        rail.setActiveTool("adjust")
        XCTAssertEqual(rail.activeToolID, "adjust")

        rail.setContext(EditorRailContext(
            chipTitle: "Text", chipSystemImage: "textformat",
            tools: [EditorTool(id: "edit", title: "Edit",
                               systemImage: "keyboard", accessibilityIdentifier: "editTextTool")]))

        XCTAssertNil(rail.activeToolID,
                     "A tool no longer present after a context swap must not stay silently active")
    }

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

    func testThePanelTitleIsCentredOnThePanel() {
        // Centred on the panel, not on the space beside the close chip: a title a
        // half-chip off centre is felt before it is seen.
        let panel = EditorPanel()
        panel.frame = CGRect(x: 0, y: 0, width: 402, height: 120)
        panel.show(UIView(), title: "Background", animated: false)
        panel.layoutIfNeeded()

        let title = panel.titleLabelForLayout
        XCTAssertEqual(title.text, "Background", "the title is shown as given, not shouted")
        XCTAssertEqual(title.center.x, panel.bounds.midX, accuracy: 0.5)

        let close = panel.closeButtonForHitTesting
        XCTAssertEqual(close.center.y, title.center.y, accuracy: 0.5,
                       "the close chip sits on the title's line")
        XCTAssertEqual(close.frame.maxX, panel.bounds.maxX - 16, accuracy: 0.5)
    }

    func testTheCloseControlReportsThrough() {
        let panel = EditorPanel()
        panel.frame = CGRect(x: 0, y: 0, width: 402, height: 120)
        panel.show(UIView(), title: "Layout", animated: false)
        panel.layoutIfNeeded()
        var closed = false
        panel.onClose = { closed = true }

        panel.simulateClose()

        XCTAssertTrue(closed)

        // Regression check for a zero-height/width control: a close button whose
        // content was pinned only by center constraints (with nothing sizing its
        // own bounds) resolves to frame == .zero and cannot be hit-tested, while
        // still drawing correctly and passing every other assertion here —
        // simulateClose() drives touchUpInside directly and never hit-tests.
        // Force real layout and hit-test the button's own visual centre.
        let button = panel.closeButtonForHitTesting
        XCTAssertGreaterThan(button.bounds.width, 0, "Close button must derive a real width")
        XCTAssertGreaterThan(button.bounds.height, 0, "Close button must derive a real height")
        XCTAssertNotNil(button.accessibilityLabel)

        let centre = button.convert(CGPoint(x: button.bounds.midX, y: button.bounds.midY), to: panel)
        let hit = panel.hitTest(centre, with: nil)
        XCTAssertTrue(hit?.isDescendant(of: button) ?? false,
                     "Hit-testing the close button's visual centre must reach the button itself")
    }

    func testAnInterruptedHideAnimationDoesNotTearDownTheNextPanel() {
        // Regression test for the primary interaction (rapid panel switching):
        // hide(animated:)'s completion reads `self.content` at fire time, and
        // setVisible's completion unconditionally writes `isHidden`. If a show(B)
        // lands while A's hide animation is still in flight, A's stale completion
        // fires afterward, sees `content` is now B, tears B down, and hides the
        // panel — with `isPresenting` left `true` and nothing to re-show B.
        // All of the panel tests above use `animated: false`, which takes the
        // synchronous branch in `setVisible` and never exercises this race.
        let panel = EditorPanel()
        let a = UIView()
        let b = UIView()

        panel.show(a, title: "A", animated: true)
        panel.hide(animated: true)
        panel.show(b, title: "B", animated: true)

        let settled = expectation(description: "panel settles past the animation duration")
        DispatchQueue.main.asyncAfter(deadline: .now() + Theme.Motion.quick + 0.2) {
            settled.fulfill()
        }
        wait(for: [settled], timeout: Theme.Motion.quick + 1)

        XCTAssertTrue(panel.isPresenting, "B is showing; isPresenting must reflect that")
        XCTAssertEqual(panel.currentTitle, "B")
        XCTAssertNotNil(b.superview, "B's content must still be installed")
        XCTAssertFalse(panel.isHidden, "The panel must still be visible with B showing")
    }
}
