//
//  ImageFilterProcessor.swift
//  ClaudeCollage
//
//  Step 01 (perf) — applies per-cell colour filters via a single shared,
//  GPU-backed CIContext. Extracted so both the live canvas and the export
//  compositor reuse one context (creating a CIContext is expensive, and doing
//  it per render was part of the cost). Filtering runs OFF the geometry hot
//  path — only when a cell's filters actually change.
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreGraphics

final class ImageFilterProcessor: @unchecked Sendable {

    /// One shared instance so the CIContext (and its GPU resources) is reused.
    static let shared = ImageFilterProcessor()

    private let context: CIContext

    init() {
        self.context = CIContext(options: [.useSoftwareRenderer: false])
    }

    /// Returns `source` with `filters` applied, or `source` unchanged when the
    /// filters are at their defaults (the common case — no Core Image work).
    func apply(_ filters: CellFilters, to source: CGImage) -> CGImage {
        guard filters != CellFilters() else { return source }

        var ciImage = CIImage(cgImage: source)
        let extent = ciImage.extent

        let colorControls = CIFilter.colorControls()
        colorControls.inputImage = ciImage
        colorControls.brightness = Float(filters.brightness)
        colorControls.contrast = Float(filters.contrast)
        colorControls.saturation = Float(filters.saturation)
        ciImage = colorControls.outputImage ?? ciImage

        if filters.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = ciImage
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 6500 + filters.warmth * 1500, y: 0)
            ciImage = temperature.outputImage ?? ciImage
        }

        if filters.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = ciImage
            sharpen.sharpness = Float(filters.sharpness)
            ciImage = sharpen.outputImage ?? ciImage
        }

        return context.createCGImage(ciImage, from: extent) ?? source
    }
}
