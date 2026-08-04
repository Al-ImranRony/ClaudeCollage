//
//  EditorControlBoundsTests.swift
//  ClaudeCollageTests
//
//  Step 04.5 batch A — the proportional border / corner-radius bounds that
//  replaced the old fixed slider caps (border 20, corner 80), which were far too
//  small against a 1080pt reference canvas and meant different things on a square
//  canvas than on a story canvas.
//
//  Also covers `CollageLayout.offersLayoutAlternatives`, the predicate that hides
//  the editor's Layout section for `.template` documents instead of highlighting a
//  grid layout the document does not use.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

@MainActor
final class EditorControlBoundsTests: XCTestCase {

    private let engine = CollageLayoutEngine()

    private func makeViewModel(
        layout: CollageLayout,
        canvasSize: CGSize = CGSize(width: 1080, height: 1080)
    ) -> GridEditorViewModel {
        GridEditorViewModel(canvasSize: canvasSize, state: GridEditorState(layout: layout))
    }

    // MARK: - Border bounds

    func testBorderCeilingIsProportionalToCanvasShorterSide() {
        // 12% of the shorter side. A single full-bleed cell is large enough that
        // the cell-safety clamp never binds, so the canvas ceiling is what shows.
        let square = makeViewModel(layout: .grid(.oneCell))
        XCTAssertEqual(square.maxBorderWidth, 1080 * 0.12, accuracy: 0.001)

        let story = makeViewModel(
            layout: .grid(.oneCell), canvasSize: CGSize(width: 1080, height: 1920))
        XCTAssertEqual(story.maxBorderWidth, 1080 * 0.12, accuracy: 0.001,
                       "Story canvas should key off the 1080 short side, not the 1920 long side")
    }

    func testBorderCeilingBeatsTheOldFixedCapByAWideMargin() {
        // The regression this batch fixes: 20pt on a 1080 canvas is 1.9%.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        XCTAssertGreaterThan(viewModel.maxBorderWidth, 20,
                             "New ceiling must exceed the old hardcoded cap of 20")
    }

    func testBorderCeilingNeverCollapsesACell() {
        // Every shipped grid, at its own maximum border, must still leave every
        // cell with positive width and height.
        for template in GridTemplate.allCases {
            let viewModel = makeViewModel(layout: .grid(template))
            let border = CGFloat(viewModel.maxBorderWidth)
            let frames = engine.layout(
                for: .grid(template), canvasSize: viewModel.canvasSize, borderWidth: border)

            XCTAssertFalse(frames.isEmpty, "\(template) produced no cells")
            for frame in frames {
                XCTAssertGreaterThan(frame.frame.width, 0,
                                     "\(template) collapsed a cell's width at max border \(border)")
                XCTAssertGreaterThan(frame.frame.height, 0,
                                     "\(template) collapsed a cell's height at max border \(border)")
            }
        }
    }

    func testDenseGridGetsATighterBorderCeilingThanASingleCell() {
        let single = makeViewModel(layout: .grid(.oneCell)).maxBorderWidth
        let dense = makeViewModel(layout: .grid(.nineGrid)).maxBorderWidth
        XCTAssertLessThanOrEqual(dense, single,
                                 "A dense grid must not allow a looser border than a single cell")
    }

    // MARK: - Corner bounds

    func testCornerCeilingReachesHalfTheSmallestCellSide() {
        // Half the smaller side is exactly the radius at which a cell becomes a
        // circle/pill, so the slider must be able to get there.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        // 2×2 on 1080 → 540pt cells → 270pt to go fully round.
        XCTAssertEqual(viewModel.maxCornerRadius, 270, accuracy: 0.001)
    }

    func testCornerCeilingBeatsTheOldFixedCap() {
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        XCTAssertGreaterThan(viewModel.maxCornerRadius, 80,
                             "New ceiling must exceed the old hardcoded cap of 80")
    }

    func testCornerCeilingIsIndependentOfCurrentBorder() {
        // Deliberate: deriving the corner scale from the *current* border would
        // make the corner slider's meaning shift while the border slider is dragged.
        let relaxed = makeViewModel(layout: .grid(.fourSquare))
        var tightState = GridEditorState(layout: .grid(.fourSquare))
        tightState.borderWidth = 100
        let tight = GridEditorViewModel(
            canvasSize: CGSize(width: 1080, height: 1080), state: tightState)

        XCTAssertEqual(relaxed.maxCornerRadius, tight.maxCornerRadius, accuracy: 0.001)
    }

    // MARK: - Preview clamps (device-QA regressions)

    func testPreviewBorderAcceptsValuesAboveTheOldFixedCap() {
        // The regression: previewBorderWidth kept clamping to `min(20, width)` after
        // the slider moved to proportional bounds, so the border froze at 20pt about
        // 15% along the new range and dragging further did nothing.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        XCTAssertGreaterThan(viewModel.maxBorderWidth, 20, "precondition")

        viewModel.previewBorderWidth(viewModel.maxBorderWidth)
        XCTAssertEqual(viewModel.state.borderWidth, viewModel.maxBorderWidth, accuracy: 0.001,
                       "The full slider travel must reach the derived ceiling")

        viewModel.previewBorderWidth(60)
        XCTAssertEqual(viewModel.state.borderWidth, 60, accuracy: 0.001,
                       "A mid-range value above 20 must apply verbatim")
    }

    func testPreviewBorderIsStillClampedToTheCeiling() {
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        viewModel.previewBorderWidth(10_000)
        XCTAssertEqual(viewModel.state.borderWidth, viewModel.maxBorderWidth, accuracy: 0.001)
        viewModel.previewBorderWidth(-5)
        XCTAssertEqual(viewModel.state.borderWidth, 0, accuracy: 0.001)
    }

    func testPreviewCornerIsClampedToTheCeiling() {
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        viewModel.previewCornerRadius(10_000)
        XCTAssertEqual(viewModel.state.cornerRadius, viewModel.maxCornerRadius, accuracy: 0.001)
    }

    func testEverySliderPositionMovesTheBorder() {
        // Walks the slider end to end: each step must produce a strictly larger
        // border, which is exactly what stopped happening past the old cap.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        var previous = -1.0
        for step in 0 ... 10 {
            let fraction = Double(step) / 10
            viewModel.previewBorderWidth(fraction * viewModel.maxBorderWidth)
            XCTAssertGreaterThan(viewModel.state.borderWidth, previous,
                                 "Slider at \(Int(fraction * 100))% did not move the border")
            previous = viewModel.state.borderWidth
        }
    }

    // MARK: - Live-drag update routing

    func testBorderDragFiresGeometryOnlyNotAFullRebuild() {
        // `onChange` drives a full canvas reconfigure: every CGImage re-wrapped,
        // every sticker view torn down and re-rasterized. At slider frequency that
        // is what made the canvas stutter mid-drag. A border tick must take the
        // geometry-only route.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        var fullRebuilds = 0
        var geometryUpdates = 0
        viewModel.onChange = { fullRebuilds += 1 }
        viewModel.onGeometryChange = { geometryUpdates += 1 }

        for step in 1 ... 20 {
            viewModel.previewBorderWidth(Double(step) * 2)
        }

        XCTAssertEqual(geometryUpdates, 20, "Every tick repositions the cells")
        XCTAssertEqual(fullRebuilds, 0, "…and none of them rebuilds the canvas")
    }

    func testCornerDragFiresGeometryOnlyNotAFullRebuild() {
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        var fullRebuilds = 0
        var geometryUpdates = 0
        viewModel.onChange = { fullRebuilds += 1 }
        viewModel.onGeometryChange = { geometryUpdates += 1 }

        for step in 1 ... 20 {
            viewModel.previewCornerRadius(Double(step) * 2)
        }

        XCTAssertEqual(geometryUpdates, 20)
        XCTAssertEqual(fullRebuilds, 0)
    }

    func testRepeatedIdenticalValuesDoNoWorkAtAll() {
        // UISlider emits valueChanged far more often than the value actually moves.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        var geometryUpdates = 0
        viewModel.onGeometryChange = { geometryUpdates += 1 }

        viewModel.previewBorderWidth(30)
        for _ in 0 ..< 10 { viewModel.previewBorderWidth(30) }

        XCTAssertEqual(geometryUpdates, 1, "An unchanged value must not redraw")
    }

    func testDiscreteEditsStillTakeTheFullPath() {
        // Only the live drags are cheap; a layout change still needs a real rebuild
        // because the cell count and clip shapes change.
        let viewModel = makeViewModel(layout: .grid(.fourSquare))
        var fullRebuilds = 0
        viewModel.onChange = { fullRebuilds += 1 }
        viewModel.onGeometryChange = { XCTFail("A layout change is not geometry-only") }

        viewModel.setLayout(.grid(.nineGrid))
        XCTAssertEqual(fullRebuilds, 1)
    }

    // MARK: - Layout alternatives predicate

    func testGridAndPolygonLayoutsOfferAlternatives() {
        XCTAssertTrue(CollageLayout.grid(.fourSquare).offersLayoutAlternatives)
        XCTAssertTrue(CollageLayout.polygon(.diagonalLeft).offersLayoutAlternatives)
    }

    func testTemplateLayoutOffersNoAlternatives() {
        // The regression: a `.template` document used to show the Layout picker
        // with `.twoUpHorizontal` highlighted, claiming a selection it never had.
        let template = TemplateLayout(
            templateID: "editorial-3up",
            name: "Editorial 3-Up",
            aspectRatio: "4:5",
            cells: [
                TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 0.5)),
                TemplateLayoutCell(frame: CGRect(x: 0, y: 0.5, width: 0.5, height: 0.5)),
                TemplateLayoutCell(frame: CGRect(x: 0.5, y: 0.5, width: 0.5, height: 0.5)),
            ])
        let layout = CollageLayout.template(template)

        XCTAssertFalse(layout.offersLayoutAlternatives)
        XCTAssertNil(layout.gridTemplate,
                     "A template document has no grid template to highlight")
    }
}
