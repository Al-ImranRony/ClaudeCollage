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

public struct CellFilters: Codable, Sendable, Equatable {
    public var brightness: Double
    public var contrast: Double
    public var saturation: Double
    public var warmth: Double
    public var sharpness: Double

    public init(
        brightness: Double = 0,
        contrast: Double = 1,
        saturation: Double = 1,
        warmth: Double = 0,
        sharpness: Double = 0
    ) {
        self.brightness = brightness
        self.contrast = contrast
        self.saturation = saturation
        self.warmth = warmth
        self.sharpness = sharpness
    }
}
