//
//  ImageFilterProcessor.swift
//  Caroullage
//
//  Step 01 (perf) — applies per-cell colour filters via a single shared,
//  GPU-backed CIContext. Extracted so both the live canvas and the export
//  compositor reuse one context (creating a CIContext is expensive, and doing
//  it per render was part of the cost). Filtering runs OFF the geometry hot
//  path — only when a cell's filters actually change.
//
//  The chain, in order:
//   1. the cell's look (`FilterLook`): its photo effect, then its recipe of
//      adjustments, blended over the original at `lookIntensity`;
//   2. the user's manual adjustments, on top of whatever the look produced.
//
//  Preview and export cannot drift: both display the one filtered `CGImage`
//  this produces from the cell's downsampled source.
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

        let ciImage = CIImage(cgImage: source)
        let extent = ciImage.extent
        let filtered = applyToCIImage(filters, ciImage)
        return context.createCGImage(filtered, from: extent) ?? source
    }

    /// The same chain without the CGImage round trip, for the camera's live
    /// preview: a frame arrives as a `CIImage` and is drawn straight back out.
    func applyToCIImage(_ filters: CellFilters, _ source: CIImage) -> CIImage {
        guard filters != CellFilters() else { return source }
        let extent = source.extent

        var image = source
        if let id = filters.lookID, let look = FilterLook.look(id: id) {
            let styled = applyLook(look, to: source)
            let amount = min(max(filters.lookIntensity, 0), 1)
            if amount >= 0.999 {
                image = styled
            } else if amount > 0.001 {
                let blend = CIFilter.dissolveTransition()
                blend.inputImage = source
                blend.targetImage = styled
                blend.time = Float(amount)
                image = blend.outputImage ?? styled
            }
        }
        image = applyAdjustments(filters.manualOnly, to: image, extent: extent)
        return image.cropped(to: extent)
    }

    // MARK: - Stages

    private func applyLook(_ look: FilterLook, to source: CIImage) -> CIImage {
        var image = source
        if let effect = look.effect, let filter = CIFilter(name: effect.filterName) {
            filter.setValue(image, forKey: kCIInputImageKey)
            image = filter.outputImage ?? image
        }
        return applyAdjustments(look.adjust, to: image, extent: source.extent)
    }

    /// The manual adjustment chain. Each stage is skipped at its neutral value,
    /// so an untouched slider costs nothing.
    private func applyAdjustments(_ filters: CellFilters, to source: CIImage, extent: CGRect) -> CIImage {
        guard filters != CellFilters() else { return source }
        var ciImage = source

        if filters.brightness != 0 || filters.contrast != 1 || filters.saturation != 1 {
            let colorControls = CIFilter.colorControls()
            colorControls.inputImage = ciImage
            colorControls.brightness = Float(filters.brightness)
            colorControls.contrast = Float(filters.contrast)
            colorControls.saturation = Float(filters.saturation)
            ciImage = colorControls.outputImage ?? ciImage
        }

        if filters.warmth != 0 {
            let temperature = CIFilter.temperatureAndTint()
            temperature.inputImage = ciImage
            temperature.neutral = CIVector(x: 6500, y: 0)
            temperature.targetNeutral = CIVector(x: 6500 + filters.warmth * 1500, y: 0)
            ciImage = temperature.outputImage ?? ciImage
        }

        if filters.highlights != 0 || filters.shadows != 0 || filters.fade != 0 {
            ciImage = Self.toneCurve(filters, ciImage)
        }

        if filters.sharpness > 0 {
            let sharpen = CIFilter.sharpenLuminance()
            sharpen.inputImage = ciImage
            sharpen.sharpness = Float(filters.sharpness)
            ciImage = sharpen.outputImage ?? ciImage
        }

        if filters.vignette > 0 {
            let vignette = CIFilter.vignetteEffect()
            vignette.inputImage = ciImage
            vignette.center = CGPoint(x: extent.midX, y: extent.midY)
            vignette.radius = Float(min(extent.width, extent.height) * 0.6)
            vignette.intensity = Float(min(filters.vignette, 1))
            vignette.falloff = 0.6
            ciImage = vignette.outputImage ?? ciImage
        }

        if filters.grain > 0 {
            ciImage = Self.grain(amount: filters.grain, over: ciImage, extent: extent)
        }

        return ciImage
    }

    /// Highlights, shadows and fade as one five-point tone curve: the curve keeps
    /// its midpoint, so each control moves only its own end of the range.
    static func toneCurve(_ filters: CellFilters, _ image: CIImage) -> CIImage {
        func clamp(_ v: Double) -> CGFloat { CGFloat(min(max(v, 0), 1)) }
        let curve = CIFilter.toneCurve()
        curve.inputImage = image
        curve.point0 = CGPoint(x: 0, y: clamp(filters.fade * 0.18))
        curve.point1 = CGPoint(x: 0.25, y: clamp(0.25 + filters.shadows * 0.12 + filters.fade * 0.07))
        curve.point2 = CGPoint(x: 0.5, y: 0.5)
        curve.point3 = CGPoint(x: 0.75, y: clamp(0.75 + filters.highlights * 0.12))
        curve.point4 = CGPoint(x: 1, y: clamp(1 - filters.fade * 0.05))
        return curve.outputImage ?? image
    }

    /// Monochrome grain: `CIRandomGenerator` is deterministic, so the same cell
    /// gets the same grain on every render — preview, thumbnail and export.
    /// Noise is pulled toward mid-grey by `amount` and soft-light blended, so
    /// grey is a no-op and the grain never shifts the picture's overall tone.
    static func grain(amount: Double, over image: CIImage, extent: CGRect) -> CIImage {
        let strength = CGFloat(min(amount, 1)) * 0.6
        guard let noise = CIFilter.randomGenerator().outputImage else { return image }
        let channel = CIVector(x: strength, y: 0, z: 0, w: 0)
        let bias = (1 - strength) * 0.5
        let mono = noise
            .applyingFilter("CIColorMatrix", parameters: [
                "inputRVector": channel, "inputGVector": channel, "inputBVector": channel,
                "inputAVector": CIVector(x: 0, y: 0, z: 0, w: 1),
                "inputBiasVector": CIVector(x: bias, y: bias, z: bias, w: 0),
            ])
            .cropped(to: extent)
        let blend = CIFilter.softLightBlendMode()
        blend.inputImage = mono
        blend.backgroundImage = image
        return blend.outputImage ?? image
    }
}
