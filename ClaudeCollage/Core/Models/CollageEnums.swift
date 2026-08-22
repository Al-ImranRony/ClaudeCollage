//
//  CollageEnums.swift
//  ClaudeCollage
//
//  Shared enums for collage models. Stub for Step 00; expanded in subsequent steps.
//

import Foundation

public enum CollageMode: String, Codable, Sendable, CaseIterable {
    case grid
    case polygon
    case template
    case carousel
    case video

    /// SF Symbol the gallery badges a card with. A masonry grid mixes every
    /// mode at every proportion, so the shape of a card no longer implies what
    /// it is and the badge has to say so.
    public var badgeSymbolName: String {
        switch self {
        case .grid: return "square.grid.2x2.fill"
        case .polygon: return "triangle.fill"
        case .template: return "sparkles"
        case .carousel: return "rectangle.on.rectangle.angled"
        case .video: return "play.fill"
        }
    }

    /// Short user-facing label for a project card's subtitle.
    public var displayName: String {
        switch self {
        case .grid: return "Grid"
        case .polygon: return "Shapes"
        case .template: return "Template"
        case .carousel: return "Carousel"
        case .video: return "Video"
        }
    }
}

public enum CarouselType: String, Codable, Sendable, CaseIterable {
    case panoramic
    case matched
    case scrollThrough
    case gridPreview
}

public enum CellShape: String, Codable, Sendable, CaseIterable {
    case rectangle
    case diagonal
    case triangle
    case hexagon
    case circle
    case oval
    case custom
}
