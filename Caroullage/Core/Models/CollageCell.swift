//
//  CollageCell.swift
//  Caroullage
//
//  SwiftData model for one cell inside a collage. Stub for Step 00.
//

import Foundation
import SwiftData
import CoreGraphics

@Model
public final class CollageCell {

    @Attribute(.unique) public var id: UUID
    public var index: Int
    public var frameIndex: Int?
    public var shapeRaw: String
    // Normalized 0.0–1.0 layout frame in canvas coordinates.
    public var layoutX: Double
    public var layoutY: Double
    public var layoutWidth: Double
    public var layoutHeight: Double
    public var photoAssetID: String?
    public var videoAssetID: String?
    public var transform: CellTransform
    public var filters: CellFilters
    public var borderWidth: Double
    public var cornerRadius: Double
    public var textOverlays: [TextOverlay]

    public init(
        id: UUID = UUID(),
        index: Int,
        frameIndex: Int? = nil,
        shape: CellShape = .rectangle,
        layoutFrame: CGRect = .zero,
        photoAssetID: String? = nil,
        videoAssetID: String? = nil,
        transform: CellTransform = CellTransform(),
        filters: CellFilters = CellFilters(),
        borderWidth: CGFloat = 0,
        cornerRadius: CGFloat = 0,
        textOverlays: [TextOverlay] = []
    ) {
        self.id = id
        self.index = index
        self.frameIndex = frameIndex
        self.shapeRaw = shape.rawValue
        self.layoutX = Double(layoutFrame.origin.x)
        self.layoutY = Double(layoutFrame.origin.y)
        self.layoutWidth = Double(layoutFrame.size.width)
        self.layoutHeight = Double(layoutFrame.size.height)
        self.photoAssetID = photoAssetID
        self.videoAssetID = videoAssetID
        self.transform = transform
        self.filters = filters
        self.borderWidth = Double(borderWidth)
        self.cornerRadius = Double(cornerRadius)
        self.textOverlays = textOverlays
    }

    public var shape: CellShape {
        get { CellShape(rawValue: shapeRaw) ?? .rectangle }
        set { shapeRaw = newValue.rawValue }
    }

    public var layoutFrame: CGRect {
        get { CGRect(x: layoutX, y: layoutY, width: layoutWidth, height: layoutHeight) }
        set {
            layoutX = Double(newValue.origin.x)
            layoutY = Double(newValue.origin.y)
            layoutWidth = Double(newValue.size.width)
            layoutHeight = Double(newValue.size.height)
        }
    }
}

// MARK: - Value types stored on CollageCell

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
