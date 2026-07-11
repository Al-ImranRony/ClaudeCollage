//
//  RenderingPerformanceTests.swift
//  ClaudeCollageTests
//
//  Step 01 (perf) — locks in the memory/CPU behaviour of the reworked pipeline:
//   • imported photos are downsampled (never held full-resolution), and
//   • export still composites at full canvas resolution from those downsampled
//     sources.
//

import XCTest
import UIKit
@testable import ClaudeCollage

final class RenderingPerformanceTests: XCTestCase {

    /// A large source image must be downsampled to the display cap, so RAM per
    /// cell stays bounded regardless of the original photo's resolution.
    func testDownsamplerCapsLongestEdge() throws {
        let bigSide: CGFloat = 3000
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        let big = UIGraphicsImageRenderer(size: CGSize(width: bigSide, height: bigSide), format: format).image { ctx in
            UIColor.systemTeal.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: bigSide, height: bigSide))
        }
        let data = try XCTUnwrap(big.jpegData(compressionQuality: 0.9))

        let downsampled = try XCTUnwrap(ImageDownsampler.downsample(data: data))
        let longest = max(downsampled.width, downsampled.height)
        XCTAssertLessThanOrEqual(
            CGFloat(longest), ImageDownsampler.displayMaxDimension,
            "Downsampled image should be capped at the display max dimension"
        )
        // And it must be materially smaller than the 3000px original.
        XCTAssertLessThan(longest, Int(bigSide))
    }

    /// Export composites at full canvas resolution even though the source image
    /// is a downsampled thumbnail.
    @MainActor
    func testExportProducesFullCanvasResolution() throws {
        let canvas = CGSize(width: 1080, height: 1080)
        let viewModel = GridEditorViewModel(canvasSize: canvas)
        viewModel.setTemplate(.fourSquare)

        // A small (downsampled-scale) source image assigned to a cell.
        let source = UIGraphicsImageRenderer(size: CGSize(width: 800, height: 800)).image { ctx in
            UIColor.systemPink.setFill()
            ctx.fill(CGRect(x: 0, y: 0, width: 800, height: 800))
        }
        let cgSource = try XCTUnwrap(source.cgImage)
        viewModel.setImage(cgSource, forCellAt: 0)

        let exported = try XCTUnwrap(viewModel.renderExport())
        XCTAssertEqual(exported.width, Int(canvas.width))
        XCTAssertEqual(exported.height, Int(canvas.height))
    }
}
