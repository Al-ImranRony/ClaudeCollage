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
