//
//  CellTransition.swift
//  ClaudeCollage
//
//  Step 04 slice 4 — an optional per-cell intro animation played at the start of a
//  video collage. Applied via layer-instruction opacity/transform ramps (crossfade
//  = opacity, slide/zoom = transform), so it composites into the export exactly as
//  it previews. Value type ⇒ persists + undoes with the rest of the cell state.
//

import Foundation

public struct CellTransition: Equatable, Sendable, Codable {

    public enum Style: String, Sendable, Codable, CaseIterable {
        case crossfade
        case slideLeft
        case slideRight
        case zoomIn
    }

    public var style: Style
    /// Length of the intro animation, in seconds (clamped ≥ 0).
    public var duration: Double

    public init(style: Style, duration: Double = 0.5) {
        self.style = style
        self.duration = max(0, duration)
    }

    private enum CodingKeys: String, CodingKey { case style, duration }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(String.self, forKey: .style) ?? ""
        self.style = Style(rawValue: raw) ?? .crossfade
        self.duration = max(0, try c.decodeIfPresent(Double.self, forKey: .duration) ?? 0.5)
    }
}
