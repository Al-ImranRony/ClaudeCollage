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
