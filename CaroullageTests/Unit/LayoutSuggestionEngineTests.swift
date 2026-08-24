//
//  LayoutSuggestionEngineTests.swift
//  CaroullageTests
//
//  Step 05 batch A — the scoring behind "AI auto-layout".
//
//  Pure geometry, so this is where the real coverage for the AI features lives:
//  Vision cannot run in the simulator, but nothing here needs it. The engine is
//  fed the face and saliency rects Vision would have produced.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class LayoutSuggestionEngineTests: XCTestCase {

    private let engine = LayoutSuggestionEngine()

    /// A face dead centre — survives almost any crop.
    private func centredFace(aspect: CGFloat) -> PhotoFeatures {
        PhotoFeatures(
            aspectRatio: aspect,
            faces: [CGRect(x: 0.4, y: 0.4, width: 0.2, height: 0.2)]
        )
    }

    /// A face hard against the left edge — the first thing a centre crop loses
    /// when a wide photo is squeezed into a narrow cell.
    private func edgeFace(aspect: CGFloat) -> PhotoFeatures {
        PhotoFeatures(
            aspectRatio: aspect,
            faces: [CGRect(x: 0.02, y: 0.4, width: 0.16, height: 0.2)]
        )
    }

    // MARK: - Crop geometry

    func testWidePhotoInSquareCellLosesItsSides() {
        let visible = LayoutSuggestionEngine.centreCropRect(photoAspect: 2, cellAspect: 1)
        XCTAssertEqual(visible.width, 0.5, accuracy: 0.001, "Half the width survives")
        XCTAssertEqual(visible.height, 1, accuracy: 0.001, "Full height survives")
        XCTAssertEqual(visible.midX, 0.5, accuracy: 0.001, "Crop stays centred")
    }

    func testTallPhotoInSquareCellLosesTopAndBottom() {
        let visible = LayoutSuggestionEngine.centreCropRect(photoAspect: 0.5, cellAspect: 1)
        XCTAssertEqual(visible.height, 0.5, accuracy: 0.001)
        XCTAssertEqual(visible.width, 1, accuracy: 0.001)
        XCTAssertEqual(visible.midY, 0.5, accuracy: 0.001)
    }

    func testMatchingAspectsCropNothing() {
        let visible = LayoutSuggestionEngine.centreCropRect(photoAspect: 1.5, cellAspect: 1.5)
        XCTAssertEqual(visible, CGRect(x: 0, y: 0, width: 1, height: 1))
    }

    func testAspectAffinityPeaksWhenShapesMatch() {
        XCTAssertEqual(LayoutSuggestionEngine.aspectAffinity(1.5, 1.5), 1, accuracy: 0.001)
        // Symmetric: being twice as wide is as bad as being half as wide.
        XCTAssertEqual(LayoutSuggestionEngine.aspectAffinity(2, 1),
                       LayoutSuggestionEngine.aspectAffinity(1, 2), accuracy: 0.001)
        XCTAssertLessThan(LayoutSuggestionEngine.aspectAffinity(3, 1),
                          LayoutSuggestionEngine.aspectAffinity(1.2, 1))
    }

    // MARK: - Scoring

    func testProtectingAFaceBeatsCroppingIt() {
        // Same photo, same template; only where the face sits differs.
        let safe = engine.score(.oneCell, for: [centredFace(aspect: 2)])
        let atRisk = engine.score(.oneCell, for: [edgeFace(aspect: 2)])
        XCTAssertGreaterThan(safe, atRisk,
                             "A layout that keeps the face must outscore one that slices it")
    }

    func testScoreIsBoundedToUnitRange() {
        for template in GridTemplate.allCases {
            let score = engine.score(template, for: [centredFace(aspect: 1), centredFace(aspect: 1)])
            XCTAssertGreaterThanOrEqual(score, 0, "\(template) scored below 0")
            XCTAssertLessThanOrEqual(score, 1, "\(template) scored above 1")
        }
    }

    func testFacesOutweighSaliencyWhenBothCompete() {
        // Weights are relative WITHIN a photo — scoring normalises by total
        // weight, so a lone face and a lone salient blob score the same (losing
        // the only subject is equally bad either way). The weighting shows up
        // when both are present and only one can survive the crop.
        let edge = CGRect(x: 0.02, y: 0.4, width: 0.16, height: 0.2)
        let centre = CGRect(x: 0.42, y: 0.4, width: 0.16, height: 0.2)

        let faceProtected = PhotoFeatures(
            aspectRatio: 2, faces: [centre], salientRegions: [edge])
        let faceSacrificed = PhotoFeatures(
            aspectRatio: 2, faces: [edge], salientRegions: [centre])

        XCTAssertGreaterThan(
            engine.score(.oneCell, for: [faceProtected]),
            engine.score(.oneCell, for: [faceSacrificed]),
            "Keeping the face and losing the salient area must beat the reverse")
    }

    func testALoneFaceAndALoneSalientRegionScoreAlike() {
        // Pins the normalisation above, so a future change to the weights cannot
        // silently make a single-region photo score differently by type.
        let rect = CGRect(x: 0.02, y: 0.4, width: 0.16, height: 0.2)
        let face = PhotoFeatures(aspectRatio: 2, faces: [rect])
        let salient = PhotoFeatures(aspectRatio: 2, salientRegions: [rect])

        XCTAssertEqual(engine.score(.oneCell, for: [face]),
                       engine.score(.oneCell, for: [salient]), accuracy: 0.0001)
    }

    func testPhotoWithNoDetectionsScoresOnShapeAlone() {
        // Nothing detected — a 2:1 photo should still prefer a cell it fits.
        let plain = PhotoFeatures(aspectRatio: 2)
        let square = engine.score(.oneCell, for: [plain])
        let sideBySide = engine.score(.twoUpHorizontal, for: [plain, plain])
        XCTAssertGreaterThan(square, 0)
        XCTAssertGreaterThan(sideBySide, 0)
    }

    // MARK: - Suggestions

    func testSuggestionsAreRankedAndLimited() {
        let photos = Array(repeating: centredFace(aspect: 1), count: 4)
        let suggestions = engine.suggestions(for: photos, limit: 3)

        XCTAssertEqual(suggestions.count, 3)
        XCTAssertEqual(suggestions, suggestions.sorted { $0.score > $1.score },
                       "Best first")
    }

    func testSuggestionsAreDeterministic() {
        // The row must not reshuffle between identical runs.
        let photos = Array(repeating: centredFace(aspect: 1), count: 4)
        XCTAssertEqual(engine.suggestions(for: photos), engine.suggestions(for: photos))
    }

    func testFourPhotosPreferAFourCellGrid() {
        // The headline behaviour: the count you have should drive the suggestion.
        let photos = Array(repeating: centredFace(aspect: 1), count: 4)
        let best = engine.suggestions(for: photos, limit: 1).first
        XCTAssertEqual(best?.template.cellCount, 4,
                       "Four square photos should suggest a four-cell grid")
    }

    func testTwoPhotosDoNotSuggestANineCellGrid() {
        let photos = Array(repeating: centredFace(aspect: 1), count: 2)
        let templates = engine.suggestions(for: photos, limit: 3).map(\.template)
        XCTAssertFalse(templates.contains(.nineGrid),
                       "Seven empty cells should never be a top suggestion")
    }

    func testEmptyInputYieldsNoSuggestions() {
        XCTAssertTrue(engine.suggestions(for: []).isEmpty)
        XCTAssertEqual(engine.score(.fourSquare, for: []), 0)
    }

    func testZeroLimitYieldsNothing() {
        XCTAssertTrue(engine.suggestions(for: [centredFace(aspect: 1)], limit: 0).isEmpty)
    }

    func testDegenerateAspectRatioIsSurvivable() {
        // A zero or negative aspect must not produce NaN and poison the sort.
        let broken = PhotoFeatures(aspectRatio: 0)
        let suggestions = engine.suggestions(for: [broken])
        XCTAssertFalse(suggestions.isEmpty)
        for suggestion in suggestions {
            XCTAssertFalse(suggestion.score.isNaN, "\(suggestion.template) scored NaN")
        }
    }
}
