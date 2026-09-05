//
//  TextStyle.swift
//  Caroullage
//
//  How a text overlay is PRESENTED, as distinct from what it says and how it is
//  typeset. White text over bright footage is unreadable, and bright footage is
//  most of what people shoot — these are the treatments that fix that, shipped as
//  one-tap presets rather than five loose sliders.
//
//  `width` is in POINTS ON THE REFERENCE CANVAS, the same convention as
//  `TextOverlay.fontSize`, so a renderer scales it by the same `fontScale`.
//

import Foundation

public struct TextStyle: Codable, Sendable, Equatable {

    public enum Kind: String, Codable, Sendable, CaseIterable {
        /// No treatment.
        case plain
        /// Soft drop shadow.
        case shadow
        /// Outline around the glyphs.
        case stroke
        /// Solid rounded rectangle behind the whole text block.
        case pill
        /// Solid rectangle hugging the text, marker-pen style.
        case highlight
        /// Coloured outer glow.
        case glow
    }

    public var kind: Kind
    /// Stroke, pill, highlight or glow colour. Ignored by `.plain`.
    public var colorHex: String
    /// Stroke width, glow radius, or pill corner inset — reference-canvas points.
    public var width: Double

    public init(kind: Kind = .plain, colorHex: String = "#000000", width: Double = 6) {
        self.kind = kind
        self.colorHex = colorHex
        self.width = max(0, width)
    }

    private enum CodingKeys: String, CodingKey { case kind, colorHex, width }

    /// Defensive, matching `TextOverlay.init(from:)`: an unknown kind from a future
    /// build decodes to `.plain` rather than throwing and losing the whole project.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TextStyle()
        let raw = try c.decodeIfPresent(String.self, forKey: .kind)
        self.kind = raw.flatMap(Kind.init(rawValue:)) ?? fallback.kind
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? fallback.colorHex
        self.width = max(0, try c.decodeIfPresent(Double.self, forKey: .width) ?? fallback.width)
    }
}
