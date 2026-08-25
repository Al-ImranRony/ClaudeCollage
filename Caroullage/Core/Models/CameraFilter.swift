//
//  CameraFilter.swift
//  Caroullage
//
//  Step 06 UI pass — the looks offered in the camera.
//
//  Deliberately built on `CellFilters`, the same value the editor already
//  applies per cell, so a shot taken through "Golden" and a cell filtered to
//  "Golden" go through one code path and come out identical. Adding a look here
//  is a new case, not a new pipeline.
//

import CoreGraphics
import Foundation

public enum CameraFilter: String, CaseIterable, Sendable, Equatable {
    case original
    case golden
    case fade
    case cool
    case vivid
    case mono

    /// Strip order: the untouched picture first, then warm to cool, then mono.
    public static let all: [CameraFilter] = [.original, .golden, .fade, .cool, .vivid, .mono]

    public var title: String {
        switch self {
        case .original: return String(localized: "Original")
        case .golden: return String(localized: "Golden")
        case .fade: return String(localized: "Fade")
        case .cool: return String(localized: "Cool")
        case .vivid: return String(localized: "Vivid")
        case .mono: return String(localized: "Mono")
        }
    }

    /// What the look does, in the editor's own terms.
    public var settings: CellFilters {
        switch self {
        case .original:
            return CellFilters()
        case .golden:
            // Late-afternoon warmth, with a touch of lift so skin does not go muddy.
            return CellFilters(brightness: 0.04, contrast: 1.05, saturation: 1.12, warmth: 0.45)
        case .fade:
            // Flattened blacks and pulled-back colour: the washed film look.
            return CellFilters(brightness: 0.08, contrast: 0.88, saturation: 0.82, warmth: 0.1)
        case .cool:
            return CellFilters(brightness: 0.02, contrast: 1.08, saturation: 0.95, warmth: -0.4)
        case .vivid:
            return CellFilters(contrast: 1.15, saturation: 1.45, sharpness: 0.35)
        case .mono:
            return CellFilters(contrast: 1.2, saturation: 0)
        }
    }

    /// Applies the look. `original` returns the source untouched — the processor
    /// short-circuits on default settings, so this costs nothing.
    public func apply(to image: CGImage) -> CGImage {
        ImageFilterProcessor.shared.apply(settings, to: image)
    }
}
