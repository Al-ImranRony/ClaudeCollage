//
//  VideoTemplateTests.swift
//  CaroullageTests
//
//  The bundled video templates, the camera pan they may carry, the grids they
//  added, and the editor state a template opens into.
//

import XCTest
import CoreGraphics
@testable import Caroullage

@MainActor
final class VideoTemplateTests: XCTestCase {

    // MARK: - Grids

    func testThreeRowsStacksFullWidthThirds() {
        let cells = GridTemplate.threeRows.normalizedCells
        XCTAssertEqual(cells.count, 3)
        for (index, cell) in cells.enumerated() {
            XCTAssertEqual(cell.width, 1, accuracy: 1e-9)
            XCTAssertEqual(cell.height, 1.0 / 3, accuracy: 1e-9)
            XCTAssertEqual(cell.minY, Double(index) / 3, accuracy: 1e-9)
        }
    }

    func testThreeColumnsSitsSideBySide() {
        let cells = GridTemplate.threeColumns.normalizedCells
        XCTAssertEqual(cells.map(\.minX), [0, 1.0 / 3, 2.0 / 3])
        XCTAssertTrue(cells.allSatisfy { $0.height == 1 })
    }

    // MARK: - Pan

    func testPanStripIsExtentFramesLong() {
        let pan = CanvasPan(axis: .horizontal, extent: 2.5)
        XCTAssertEqual(pan.stripSize(for: CGSize(width: 1920, height: 1080)),
                       CGSize(width: 4800, height: 1080))
        let vertical = CanvasPan(axis: .vertical, extent: 2)
        XCTAssertEqual(vertical.stripSize(for: CGSize(width: 1080, height: 1920)),
                       CGSize(width: 1080, height: 3840))
    }

    func testCameraGlidesLinearlyFromStartToEnd() {
        let pan = CanvasPan(axis: .horizontal, extent: 3)
        let frame = CGSize(width: 100, height: 50)
        XCTAssertEqual(pan.cameraOffset(at: 0, duration: 10, canvas: frame), .zero)
        XCTAssertEqual(pan.cameraOffset(at: 5, duration: 10, canvas: frame).x, 100, accuracy: 1e-9)
        XCTAssertEqual(pan.cameraOffset(at: 10, duration: 10, canvas: frame).x, 200, accuracy: 1e-9,
                       "ends with the strip's last frame in view")
        XCTAssertEqual(pan.cameraOffset(at: 99, duration: 10, canvas: frame).x, 200, accuracy: 1e-9,
                       "clamped past the end")
    }

    func testPanExtentIsClampedAndDecodesDefensively() throws {
        XCTAssertEqual(CanvasPan(extent: 40).extent, CanvasPan.extentRange.upperBound)
        XCTAssertEqual(CanvasPan(extent: 0.2).extent, 1)
        let decoded = try JSONDecoder().decode(
            CanvasPan.self, from: Data(#"{"axis":"diagonal","extent":1e9}"#.utf8))
        XCTAssertEqual(decoded.axis, .horizontal)
        XCTAssertEqual(decoded.extent, CanvasPan.extentRange.upperBound)
    }

    func testProjectDataWithoutPanStillDecodes() throws {
        let data = try JSONEncoder().encode(VideoProjectData())
        let decoded = try JSONDecoder().decode(VideoProjectData.self, from: data)
        XCTAssertNil(decoded.pan)
    }

    func testProjectDataRoundTripsPan() throws {
        let original = VideoProjectData(pan: CanvasPan(axis: .vertical, extent: 2))
        let decoded = try JSONDecoder().decode(
            VideoProjectData.self, from: try JSONEncoder().encode(original))
        XCTAssertEqual(decoded.pan, original.pan)
    }

    // MARK: - Catalog

    func testCatalogIdsAreUnique() {
        let ids = VideoTemplateCatalog.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count)
        XCTAssertEqual(ids.count, 4)
    }

    func testEveryTemplateLaysOutItsSlotsInsideItsLayoutSpace() {
        for template in VideoTemplateCatalog.all {
            let viewModel = VideoEditorViewModel(template: template)
            let bounds = CGRect(origin: .zero, size: viewModel.layoutSize)
            XCTAssertEqual(viewModel.cellCount, template.slotCount, template.id)
            for cell in viewModel.cellFrames() {
                XCTAssertTrue(bounds.insetBy(dx: -0.5, dy: -0.5).contains(cell.frame), template.id)
                XCTAssertGreaterThan(cell.frame.width, 0, template.id)
            }
        }
    }

    func testEveryCaptionFitsOnItsCanvasAndUsesAnInstalledFace() {
        for template in VideoTemplateCatalog.all {
            for caption in template.textOverlays {
                XCTAssertTrue(CGRect(x: 0, y: 0, width: 1, height: 1).contains(caption.frame),
                              "\(template.id): \(caption.text)")
                XCTAssertNotNil(UIFont(name: caption.fontName, size: 12),
                                "\(template.id) uses \(caption.fontName), which iOS must ship")
            }
        }
    }

    func testTheReferenceLooksAreFaithful() {
        XCTAssertEqual(VideoTemplateCatalog.titleGrid.layout, .grid(.fourSquare))
        XCTAssertEqual(VideoTemplateCatalog.titleGrid.aspectRatio, "9:16")
        XCTAssertTrue(VideoTemplateCatalog.titleGrid.textOverlays.allSatisfy { $0.animation == .fade })

        XCTAssertEqual(VideoTemplateCatalog.lyricStack.layout, .grid(.threeRows))
        XCTAssertTrue(VideoTemplateCatalog.lyricStack.textOverlays.allSatisfy { $0.animation == .words })

        XCTAssertEqual(VideoTemplateCatalog.captionStack.layout, .grid(.threeRows))
        XCTAssertTrue(VideoTemplateCatalog.captionStack.textOverlays.allSatisfy {
            $0.animation == .wordFade && $0.style.kind == .box })

        let filmstrip = VideoTemplateCatalog.travelFilmstrip
        XCTAssertEqual(filmstrip.aspectRatio, "16:9")
        XCTAssertEqual(filmstrip.pan?.axis, .horizontal)
        XCTAssertEqual(filmstrip.slotCount, 5)
    }

    func testLyricCaptionsPlayInSequenceWithoutOverlapping() {
        let captions = VideoTemplateCatalog.lyricStack.textOverlays
        for (a, b) in zip(captions, captions.dropFirst()) {
            XCTAssertLessThanOrEqual(a.endTime ?? 0, b.startTime ?? 0)
        }
    }

    // MARK: - Opening a template

    func testATemplateOpensEmptyWithItsCaptionsAndCamera() {
        let template = VideoTemplateCatalog.travelFilmstrip
        let viewModel = VideoEditorViewModel(template: template)
        XCTAssertEqual(viewModel.canvasSize, CanvasSize.size(forAspectRatio: "16:9"))
        XCTAssertEqual(viewModel.pan, template.pan)
        XCTAssertEqual(viewModel.layoutSize.width, viewModel.canvasSize.width * 2.5, accuracy: 1e-6)
        XCTAssertFalse(viewModel.hasContent)
        XCTAssertEqual(viewModel.textOverlays.map(\.text), template.textOverlays.map(\.text))
        XCTAssertEqual(viewModel.stickerOverlays.count, template.stickerOverlays.count)
        XCTAssertFalse(viewModel.canUndo, "opening a template is not an edit")
    }

    func testTwoProjectsFromOneTemplateDoNotShareOverlayIds() {
        let a = VideoEditorViewModel(template: VideoTemplateCatalog.captionStack)
        let b = VideoEditorViewModel(template: VideoTemplateCatalog.captionStack)
        XCTAssertTrue(Set(a.textOverlays.map(\.id)).isDisjoint(with: b.textOverlays.map(\.id)))
    }

    func testPanSurvivesPersistenceAndUndo() {
        let viewModel = VideoEditorViewModel(template: VideoTemplateCatalog.travelFilmstrip)
        XCTAssertEqual(viewModel.projectData().pan, VideoTemplateCatalog.travelFilmstrip.pan)

        viewModel.changeLayout(.grid(.threeColumns))
        viewModel.undo()
        XCTAssertEqual(viewModel.pan, VideoTemplateCatalog.travelFilmstrip.pan)

        let restored = VideoEditorViewModel(canvasSize: viewModel.canvasSize)
        restored.restore(data: viewModel.projectData(), assets: [:], musicAsset: nil)
        XCTAssertEqual(restored.pan, viewModel.pan)
        XCTAssertEqual(restored.layoutSize, viewModel.layoutSize)
    }

    func testExportScalesCaptionsWithTheRenderSize() {
        XCTAssertEqual(VideoEditorViewModel.textFontScale(
            canvas: CGSize(width: 1080, height: 1920), render: CGSize(width: 2160, height: 3840)), 2)
        XCTAssertEqual(VideoEditorViewModel.textFontScale(
            canvas: CGSize(width: 1080, height: 1920), render: nil), 1)
    }
}
