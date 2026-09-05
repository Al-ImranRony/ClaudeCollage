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
}
