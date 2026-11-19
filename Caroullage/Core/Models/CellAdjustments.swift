//
//  CellAdjustments.swift
//  Caroullage
//
//  The per-cell pan/zoom/rotation and filter values the editors store inside
//  `EditorCellState` (and so inside the JSON editor-state blob). Moved here from
//  the retired `CollageCell` model, which once stored them as schema columns.
//

import Foundation

public struct CellTransform: Codable, Sendable, Equatable {
    public var panX: Double
    public var panY: Double
    public var zoom: Double
    public var rotationRadians: Double

    public init(panX: Double = 0, panY: Double = 0, zoom: Double = 1, rotationRadians: Double = 0) {
        self.panX = panX
        self.panY = panY
        self.zoom = zoom
        self.rotationRadians = rotationRadians
    }
}

/// A cell's colour treatment: an optional named look (`lookID`, blended in at
/// `lookIntensity`) followed by the user's own manual adjustments.
///
/// Every field added after Step 01 decodes with a default (see `init(from:)`),
/// so a project saved before filters grew past the first five sliders still
/// opens unchanged — synthesized `Codable` would have thrown on the missing keys.
public struct CellFilters: Codable, Sendable, Equatable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var sharpness: Double
    /// −1…1. Lifts (or deepens) the upper tones without moving the midpoint.
    public var highlights: Double
    /// −1…1. Opens (or crushes) the lower tones without moving the midpoint.
    public var shadows: Double
    /// 0…1. Raises the black point — the washed, matte film look.
    public var fade: Double
    /// 0…1. Darkens the corners.
    public var vignette: Double
    /// 0…1. Monochrome film grain.
    public var grain: Double
    /// The `FilterLook.id` applied before the manual adjustments, or nil.
    public var lookID: String?
    /// 0…1. How much of the look is blended over the original.
    public var lookIntensity: Double

    public init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        warmth: Double = 0,
        sharpness: Double = 0,
        highlights: Double = 0,
        shadows: Double = 0,
        fade: Double = 0,
        vignette: Double = 0,
        grain: Double = 0,
        lookID: String? = nil,
        lookIntensity: Double = 1
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.sharpness = sharpness
        self.highlights = highlights
        self.shadows = shadows
        self.fade = fade
        self.vignette = vignette
        self.grain = grain
        self.lookID = lookID
        self.lookIntensity = lookIntensity
    }

    /// The same values with the look removed — the manual half of the chain.
    public var manualOnly: CellFilters {
        var copy = self
        copy.lookID = nil
        copy.lookIntensity = 1
        return copy
    }

    /// Whether any manual slider is off its neutral value.
    public var hasManualAdjustments: Bool { manualOnly != CellFilters() }

    private enum CodingKeys: String, CodingKey {
        case brightness, contrast, saturation, warmth, sharpness
        case highlights, shadows, fade, vignette, grain, lookID, lookIntensity
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let neutral = CellFilters()
        brightness = try c.decodeIfPresent(Double.self, forKey: .brightness) ?? neutral.brightness
        contrast = try c.decodeIfPresent(Double.self, forKey: .contrast) ?? neutral.contrast
        saturation = try c.decodeIfPresent(Double.self, forKey: .saturation) ?? neutral.saturation
        warmth = try c.decodeIfPresent(Double.self, forKey: .warmth) ?? neutral.warmth
        sharpness = try c.decodeIfPresent(Double.self, forKey: .sharpness) ?? neutral.sharpness
        highlights = try c.decodeIfPresent(Double.self, forKey: .highlights) ?? neutral.highlights
        shadows = try c.decodeIfPresent(Double.self, forKey: .shadows) ?? neutral.shadows
        fade = try c.decodeIfPresent(Double.self, forKey: .fade) ?? neutral.fade
        vignette = try c.decodeIfPresent(Double.self, forKey: .vignette) ?? neutral.vignette
        grain = try c.decodeIfPresent(Double.self, forKey: .grain) ?? neutral.grain
        lookID = try c.decodeIfPresent(String.self, forKey: .lookID)
        lookIntensity = try c.decodeIfPresent(Double.self, forKey: .lookIntensity) ?? neutral.lookIntensity
    }
}
