//
//  CollageEnums.swift
//  Caroullage
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

    /// The section header and chip label. `scrollThrough` and `gridPreview` are
    /// camel-cased raw values that must never reach a user, which is the whole
    /// reason this is not `rawValue.capitalized`.
    public var displayName: String {
        switch self {
        case .panoramic: return String(localized: "Panoramic")
        case .matched: return String(localized: "Matched")
        case .scrollThrough: return String(localized: "Scroll-Through")
        case .gridPreview: return String(localized: "Grid Preview")
        }
    }
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
