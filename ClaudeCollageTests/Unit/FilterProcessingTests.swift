//
//  FilterProcessingTests.swift
//  ClaudeCollageTests
//
//  Step 02 — regression coverage for the async per-cell filter path. This
//  reproduces the crash reported when editing a cell's filters: the background
//  DispatchWorkItem was inferred @MainActor-isolated under Swift 6 complete
//  concurrency and trapped when run on the filter queue.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class FilterProcessingTests: XCTestCase {

    /// A tiny opaque CGImage to feed the filter pipeline.
    private func makeImage(_ side: Int = 32) -> CGImage {
        let space = CGColorSpaceCreateDeviceRGB()
        let ctx = CGContext(
            data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0,
            space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        ctx.setFillColor(CGColor(red: 0.3, green: 0.6, blue: 0.9, alpha: 1))
        ctx.fill(CGRect(x: 0, y: 0, width: side, height: side))
        return ctx.makeImage()!
    }

    @MainActor
    func testEditingCellFiltersDeliversResultWithoutCrashing() {
        let viewModel = GridEditorViewModel(canvasSize: CGSize(width: 64, height: 64))
        viewModel.setImage(makeImage(), forCellAt: 0)

        let delivered = expectation(description: "filtered image delivered on main")
        viewModel.onCellImageChanged = { index in
            XCTAssertEqual(index, 0)
            delivered.fulfill()
        }

        var filters = CellFilters()
        filters.brightness = 0.25
        filters.contrast = 1.2
        viewModel.previewFilters(filters, forCellAt: 0)

        wait(for: [delivered], timeout: 5)
    }

    @MainActor
    func testRapidFilterEditsCoalesceWithoutCrashing() {
        let viewModel = GridEditorViewModel(canvasSize: CGSize(width: 64, height: 64))
        viewModel.setImage(makeImage(), forCellAt: 0)

        let delivered = expectation(description: "at least one result delivered")
        delivered.assertForOverFulfill = false
        viewModel.onCellImageChanged = { _ in delivered.fulfill() }

        // Simulate a fast slider drag: many rapid non-default filter updates.
        for step in 1 ... 20 {
            var filters = CellFilters()
            filters.brightness = Double(step) / 40.0
            viewModel.previewFilters(filters, forCellAt: 0)
        }

        wait(for: [delivered], timeout: 5)
    }
}
