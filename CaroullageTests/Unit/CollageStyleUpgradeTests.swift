//
//  CollageStyleUpgradeTests.swift
//  CaroullageTests
//
//  The collage editor's style upgrade: filter looks + new adjustments, drawn
//  backgrounds (gradient / pattern / photo blur), and the Frame panel's margin,
//  shadow and outline. Persistence compatibility is pinned first, because every
//  project on a user's device was saved before any of this existed.
//

import UIKit
import XCTest
@testable import Caroullage

final class CollageStyleUpgradeTests: XCTestCase {

    // MARK: - Helpers

    private func solidImage(_ side: Int = 64, r: CGFloat = 0.3, g: CGFloat = 0.6, b: CGFloat = 0.9) -> CGImage {
        let ctx = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        // A horizontal ramp, so tone curves and looks have a range to act on.
        for x in 0..<side {
            let t = CGFloat(x) / CGFloat(side - 1)
            ctx.setFillColor(CGColor(red: r * t + 0.05, green: g * t + 0.05, blue: b * t + 0.05, alpha: 1))
            ctx.fill(CGRect(x: x, y: 0, width: 1, height: side))
        }
        return ctx.makeImage()!
    }

    private func rgba(_ image: CGImage) -> [UInt8] {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &data, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        return data
    }

    /// RGB at (x, y) with y measured from the TOP, as the canvas lays it out.
    private func pixel(_ image: CGImage, x: Int, y: Int) -> (r: Int, g: Int, b: Int) {
        let data = rgba(image)
        let i = (y * image.width + x) * 4
        return (Int(data[i]), Int(data[i + 1]), Int(data[i + 2]))
    }

    // MARK: - Persistence compatibility

    func testFiltersSavedBeforeTheUpgradeStillDecode() throws {
        let legacy = #"{"brightness":0.1,"contrast":1.2,"saturation":0.9,"warmth":0.3,"sharpness":0.2}"#
        let filters = try JSONDecoder().decode(CellFilters.self, from: Data(legacy.utf8))
        XCTAssertEqual(filters, CellFilters(brightness: 0.1, contrast: 1.2, saturation: 0.9,
                                            warmth: 0.3, sharpness: 0.2))
        XCTAssertNil(filters.lookID)
        XCTAssertEqual(filters.lookIntensity, 1)
    }

    func testNewFilterFieldsRoundTrip() throws {
        let filters = CellFilters(highlights: -0.4, shadows: 0.3, fade: 0.2, vignette: 0.5,
                                  grain: 0.6, lookID: "matte", lookIntensity: 0.7)
        let decoded = try JSONDecoder().decode(CellFilters.self, from: JSONEncoder().encode(filters))
        XCTAssertEqual(decoded, filters)
    }

    func testASavedSolidBackgroundDecodesUnchanged() throws {
        // The exact shape every pre-upgrade project stored.
        let legacy = ##"{"solid":{"hex":"#FFE5EC"}}"##
        XCTAssertEqual(try JSONDecoder().decode(CollageBackground.self, from: Data(legacy.utf8)),
                       .solid(hex: "#FFE5EC"))
    }

    func testEveryNewBackgroundRoundTrips() throws {
        for background in [CollageBackground.gradient(colors: ["#000000", "#FFFFFF"], angle: 45),
                           .pattern(.gingham, ink: "#E57373", paper: "#FFFFFF"),
                           .photoBlur(dim: 0.35)] {
            let data = try JSONEncoder().encode(background)
            XCTAssertEqual(try JSONDecoder().decode(CollageBackground.self, from: data), background)
        }
    }

    func testAnEditorStateSavedBeforeFrameStyleDecodesWithNoMarginShadowOrOutline() throws {
        var legacy = try JSONSerialization.jsonObject(
            with: JSONEncoder().encode(GridEditorState())) as! [String: Any]
        legacy.removeValue(forKey: "frameStyle")
        let data = try JSONSerialization.data(withJSONObject: legacy)
        let state = try JSONDecoder().decode(GridEditorState.self, from: data)
        XCTAssertEqual(state.frameStyle, FrameStyle())
        XCTAssertNil(state.frameStyle.outerMargin, "nil keeps the old half-spacing outer gap")
    }

    // MARK: - Layout margin

    func testNilMarginIsTheOriginalLayoutExactly() {
        let engine = CollageLayoutEngine()
        let canvas = CGSize(width: 1080, height: 1080)
        XCTAssertEqual(engine.layout(for: .grid(.fourSquare), canvasSize: canvas, borderWidth: 24, margin: nil),
                       engine.layout(for: .grid(.fourSquare), canvasSize: canvas, borderWidth: 24))
    }

    func testAnExplicitMarginPutsTheOuterCellsExactlyThatFarFromTheEdge() {
        let frames = CollageLayoutEngine().layout(
            for: .grid(.fourSquare), canvasSize: CGSize(width: 1080, height: 1350),
            borderWidth: 20, margin: 60).map(\.frame)
        XCTAssertEqual(frames.map(\.minX).min()!, 60, accuracy: 0.001)
        XCTAssertEqual(frames.map(\.minY).min()!, 60, accuracy: 0.001)
        XCTAssertEqual(1080 - frames.map(\.maxX).max()!, 60, accuracy: 0.001)
        XCTAssertEqual(1350 - frames.map(\.maxY).max()!, 60, accuracy: 0.001)
        // …while the inner gap stays the spacing.
        let left = frames.filter { $0.minX < 500 }.map(\.maxX).max()!
        let right = frames.filter { $0.minX > 500 }.map(\.minX).min()!
        XCTAssertEqual(right - left, 20, accuracy: 0.001)
    }

    func testZeroMarginRunsTheCellsToTheEdge() {
        let frames = CollageLayoutEngine().layout(
            for: .grid(.twoUpHorizontal), canvasSize: CGSize(width: 1080, height: 1080),
            borderWidth: 30, margin: 0).map(\.frame)
        XCTAssertEqual(frames.map(\.minX).min()!, 0, accuracy: 0.001)
        XCTAssertEqual(frames.map(\.maxX).max()!, 1080, accuracy: 0.001)
    }

    // MARK: - Looks

    func testTheLookCatalogIsWellFormed() {
        let ids = FilterLook.all.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "ids are persisted, so they must be unique")
        XCTAssertGreaterThanOrEqual(FilterLook.all.count, 24)
        let premium = FilterLook.all.filter(\.isPremium).count
        XCTAssertEqual(Double(premium) / Double(FilterLook.all.count), 0.65, accuracy: 0.1)
        for pack in FilterPack.allCases {
            XCTAssertFalse(FilterLook.all.filter { $0.pack == pack }.isEmpty, "\(pack) has looks")
        }
        XCTAssertTrue(FilterLook.all.allSatisfy { $0.adjust.lookID == nil }, "a recipe never nests a look")
    }

    func testTheEssentialsLooksAreTheCamerasLooks() {
        // One code path: a shot through "Golden" == a cell filtered "Golden".
        for camera in CameraFilter.all where camera != .original {
            XCTAssertEqual(FilterLook.look(id: camera.rawValue)?.adjust, camera.settings)
        }
    }

    func testEveryLookChangesThePicture() {
        let source = solidImage()
        let original = rgba(source)
        for look in FilterLook.all {
            let out = ImageFilterProcessor.shared.apply(CellFilters(lookID: look.id), to: source)
            XCTAssertNotEqual(rgba(out), original, "\(look.id) did nothing")
            XCTAssertEqual(out.width, source.width)
            XCTAssertEqual(out.height, source.height)
        }
    }

    func testIntensityZeroIsTheOriginalAndHalfIsBetween() {
        let source = solidImage()
        func green(_ intensity: Double) -> Int {
            pixel(ImageFilterProcessor.shared.apply(CellFilters(lookID: "mono", lookIntensity: intensity),
                                                    to: source), x: 48, y: 10).g
        }
        let original = pixel(source, x: 48, y: 10).g
        XCTAssertEqual(green(0), original, accuracy: 1)
        let full = green(1), half = green(0.5)
        XCTAssertTrue((min(original, full)...max(original, full)).contains(half),
                      "half intensity (\(half)) lies between original (\(original)) and full (\(full))")
    }

    func testAnUnknownLookIdRendersWithoutTheLook() {
        let source = solidImage()
        let out = ImageFilterProcessor.shared.apply(CellFilters(lookID: "retired-look"), to: source)
        XCTAssertEqual(rgba(out), rgba(ImageFilterProcessor.shared.apply(CellFilters(), to: source)))
    }

    func testEachNewAdjustmentHasAnEffect() {
        let source = solidImage()
        let original = rgba(source)
        let cases: [(String, CellFilters)] = [
            ("highlights", CellFilters(highlights: 0.8)), ("shadows", CellFilters(shadows: 0.8)),
            ("fade", CellFilters(fade: 0.8)), ("vignette", CellFilters(vignette: 1)),
            ("grain", CellFilters(grain: 1)),
        ]
        for (name, filters) in cases {
            XCTAssertNotEqual(rgba(ImageFilterProcessor.shared.apply(filters, to: source)), original, name)
        }
    }

    func testGrainIsDeterministicSoPreviewAndExportMatch() {
        let source = solidImage()
        let filters = CellFilters(grain: 0.7)
        XCTAssertEqual(rgba(ImageFilterProcessor.shared.apply(filters, to: source)),
                       rgba(ImageFilterProcessor.shared.apply(filters, to: source)))
    }

    // MARK: - Rendering

    private func render(_ state: GridEditorState, photo: CGImage? = nil,
                        size: CGSize = CGSize(width: 200, height: 200)) -> CGImage {
        let vm = MainActor.assumeIsolated { () -> GridEditorViewModel in
            let vm = GridEditorViewModel(canvasSize: size, state: state)
            if let photo { vm.setImage(photo, forCellAt: 0) }
            return vm
        }
        return MainActor.assumeIsolated { vm.renderExport()! }
    }

    func testAGradientBackgroundRunsBetweenItsStops() {
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle.outerMargin = 40
        state.background = .gradient(colors: ["#FF0000", "#0000FF"], angle: 0)   // top → bottom
        let image = render(state)
        let top = pixel(image, x: 100, y: 2), bottom = pixel(image, x: 100, y: 197)
        XCTAssertGreaterThan(top.r, 200); XCTAssertLessThan(top.b, 60)
        XCTAssertGreaterThan(bottom.b, 200); XCTAssertLessThan(bottom.r, 60)
    }

    func testAPatternBackgroundDrawsBothColours() {
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle.outerMargin = 60
        state.background = .pattern(.checker, ink: "#000000", paper: "#FFFFFF")
        let data = rgba(render(state))
        var dark = 0, light = 0
        for y in 0..<50 { for x in 0..<200 {
            let v = Int(data[(y * 200 + x) * 4])
            if v < 30 { dark += 1 } else if v > 225 { light += 1 }
        } }
        XCTAssertGreaterThan(dark, 1000); XCTAssertGreaterThan(light, 1000)
    }

    func testPhotoBlurIsBuiltFromTheCollagesOwnPhoto() {
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle.outerMargin = 50
        state.background = .photoBlur(dim: 0)
        let red = solidImage(r: 1, g: 0, b: 0)
        // The test photo ramps dark → red left to right, so the right-hand margin
        // must be red. The grey fallback (#3A3A3C) would read ~58 in every channel.
        let edge = pixel(render(state, photo: red), x: 196, y: 100)
        XCTAssertGreaterThan(edge.r, 200, "the margin shows the blurred red photo, not grey")
        XCTAssertLessThan(edge.b, 60)
    }

    func testTheOutlineIsDrawnInsideTheCellInItsColour() {
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle = FrameStyle(outerMargin: 20, outlineWidth: 4, outlineHex: "#00FF00")
        let image = render(state, photo: solidImage(r: 0, g: 0, b: 0))
        let inside = pixel(image, x: 22, y: 100)      // 2pt inside the cell's left edge
        XCTAssertGreaterThan(inside.g, 200); XCTAssertLessThan(inside.r, 60)
        let outside = pixel(image, x: 17, y: 100)     // in the white margin
        XCTAssertGreaterThan(outside.r, 200, "the stroke never spills into the margin")
    }

    func testTheShadowDarkensTheMarginBelowTheCell() {
        var plain = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        plain.frameStyle.outerMargin = 30
        var shadowed = plain
        shadowed.frameStyle.shadow = 1
        let below = { (image: CGImage) in self.pixel(image, x: 100, y: 176).r }
        XCTAssertEqual(below(render(plain)), 255, accuracy: 1)
        XCTAssertLessThan(below(render(shadowed)), 245)
    }

    private func rowLuma(_ image: CGImage, y: Int, from x0: Int, to x1: Int) -> Int {
        (x0..<x1).reduce(0) { $0 + pixel(image, x: $1, y: y).r }
    }

    func testTheShadowFallsBelowTheCellNotAbove() {
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle = FrameStyle(outerMargin: 40, shadow: 1)
        let image = render(state, size: CGSize(width: 400, height: 400))
        // Cell spans 40…360; sample 6pt outside its top and bottom edges.
        XCTAssertLessThan(rowLuma(image, y: 366, from: 100, to: 300),
                          rowLuma(image, y: 33, from: 100, to: 300),
                          "a positive offset must cast the shadow downwards, as on the canvas")
    }

    func testAThumbnailCarriesTheSameShadowAsTheExport() {
        // Thumbnails (Home, carousel strip) must show the shadow the export has.
        var state = GridEditorState(layout: .grid(.oneCell), borderWidth: 0)
        state.frameStyle = FrameStyle(outerMargin: 40, shadow: 1)
        let (full, half) = MainActor.assumeIsolated { () -> (CGImage, CGImage) in
            let vm = GridEditorViewModel(canvasSize: CGSize(width: 400, height: 400), state: state)
            return (vm.renderExport()!, vm.renderThumbnail(maxDimension: 200)!)
        }
        for offset in [4, 10, 16] {   // points below the cell, at both scales
            let a = pixel(full, x: 200, y: 360 + offset).r
            let b = pixel(half, x: 100, y: (360 + offset) / 2).r
            XCTAssertEqual(a, b, accuracy: 8, "shadow at +\(offset)pt: export \(a) vs thumbnail \(b)")
        }
    }

    // MARK: - Editor wiring

    @MainActor
    func testAReleasedSliderThatChangedNothingAddsNoUndoStep() {
        let vm = GridEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080))
        var saves = 0
        vm.onCommit = { _ in saves += 1 }
        vm.commitInteractiveChange()
        XCTAssertFalse(vm.canUndo)
        XCTAssertEqual(saves, 0)
        vm.previewCornerRadius(40)
        vm.commitInteractiveChange()
        XCTAssertTrue(vm.canUndo, "a real change still records")
        XCTAssertEqual(saves, 1)
    }

    @MainActor
    func testTheFiltersPanelClosesWhenItsCellGoesAway() throws {
        let vm = GridEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080),
                                     state: GridEditorState(layout: .grid(.fourSquare)))
        let editor = GridEditorViewController(viewModel: vm)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        window.layoutIfNeeded()
        defer { window.isHidden = true }
        let rail = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
        let panel = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorPanel }.first)

        editor.selectCellForTesting(3)
        rail.simulateTap(toolID: "filters")
        XCTAssertTrue(panel.isPresenting)
        vm.setLayout(.grid(.twoUpHorizontal))   // cell 3 no longer exists
        XCTAssertFalse(panel.isPresenting, "no orphaned Filters panel for a cell that is gone")
    }

    @MainActor
    func testOutlineSwatchesSpeakAName() {
        for hex in FrameStyle.outlinePalette {
            XCTAssertFalse(OutlineColorRow.colorName(hex).contains("#"), hex)
        }
    }



    @MainActor
    func testTheBackgroundAndLayoutPickersChangeTheDocument() throws {
        // Regression: 3aa7ea8 dropped every picker's onSelect, so taps did nothing.
        let vm = GridEditorViewModel(canvasSize: CGSize(width: 1080, height: 1080),
                                     state: GridEditorState(layout: .grid(.fourSquare)))
        let editor = GridEditorViewController(viewModel: vm)
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 402, height: 874))
        window.rootViewController = editor
        window.isHidden = false
        window.layoutIfNeeded()
        defer { window.isHidden = true }

        let rail = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorToolRail }.first)
        let panel = try XCTUnwrap(editor.view.subviews.compactMap { $0 as? EditorPanel }.first)

        rail.simulateTap(toolID: "background")
        let picker = try XCTUnwrap(panel.recursiveSubviews.compactMap { $0 as? BackgroundPickerView }.first)
        let onSelect = try XCTUnwrap(picker.onSelect, "the swatch picker must be wired")
        onSelect(.black)
        XCTAssertEqual(vm.state.background, .black)

        let strip = try XCTUnwrap(panel.recursiveSubviews.compactMap { $0 as? OptionCardStrip }.first)
        XCTAssertTrue(strip.itemIDs.isSuperset(of: ["blur0", "grad0", "pat0"]))

        rail.simulateTap(toolID: "layout")
        let layoutPicker = try XCTUnwrap(panel.recursiveSubviews.compactMap { $0 as? LayoutPickerView }.first)
        try XCTUnwrap(layoutPicker.onSelect, "the layout picker must be wired")(.nineGrid)
        XCTAssertEqual(vm.state.layout, .grid(.nineGrid))
    }

    @MainActor
    func testApplyToAllCopiesTheLookToEveryFilledCell() {
        let vm = GridEditorViewModel(canvasSize: CGSize(width: 64, height: 64),
                                     state: GridEditorState(layout: .grid(.fourSquare)))
        vm.setImage(solidImage(), forCellAt: 0)
        vm.setImage(solidImage(), forCellAt: 2)
        vm.setFilters(CellFilters(lookID: "matte", lookIntensity: 0.6), forCellAt: 0)
        vm.applyFiltersToAllCells(from: 0)
        XCTAssertEqual(vm.state.cells[2].filters.lookID, "matte")
        XCTAssertEqual(vm.state.cells[2].filters.lookIntensity, 0.6)
        XCTAssertNil(vm.state.cells[1].filters.lookID, "empty cells are left alone")
        vm.undo()
        XCTAssertNil(vm.state.cells[2].filters.lookID, "Apply to All is one undo step")
        XCTAssertEqual(vm.state.cells[0].filters.lookID, "matte")
    }

    func testCarouselStyleSyncCarriesTheFrameStyle() {
        let style = FrameStyle(outerMargin: 40, shadow: 0.5, outlineWidth: 6, outlineHex: "#000000")
        let frames = [CarouselFrame(index: 0, state: GridEditorState()),
                      CarouselFrame(index: 1, state: GridEditorState())]
        let synced = CarouselService().syncEdit(change: .frameStyle(style), to: frames)
        XCTAssertTrue(synced.allSatisfy { $0.state.frameStyle == style })
        var seeded = synced
        seeded = CarouselService().addFrame(to: seeded)
        XCTAssertEqual(seeded.last?.state.frameStyle, style, "a new frame inherits the frame style")
    }
}
