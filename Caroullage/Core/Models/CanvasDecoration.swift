//
//  CanvasDecoration.swift
//  Caroullage
//
//  2026-11-21 — a flat shape a template paints between the background and the
//  photos: the white card of an instant print, the black band of a film strip
//  and its sprocket holes, a strip of washi tape, a colour block on a magazine
//  cover.
//
//  Why it exists: the looks that top collage apps lead with — instant prints,
//  film strips, photo-booth strips, scrapbook pages — are all "a photo sitting
//  on something". Cells can only hold photos and the background can only fill
//  the whole canvas, so none of those looks could be built. A decoration is the
//  missing "something".
//
//  Decorations belong to the template's design rather than to the user's
//  content. They are not selectable or editable, and changing the background
//  repaints around them rather than over them, so a polaroid stays a polaroid
//  on any colour the user picks.
//
//  Everything is normalized — frame, corner radius and shadow are fractions of
//  the canvas (radius and shadow of its SHORT side) — so a 300-px gallery
//  thumbnail and a 4K export draw the same shape without a scale parameter.
//
//  Persistence: decoded field by field with defaults, so a decoration authored
//  without a shadow or a radius still loads, and `GridEditorState` decodes a
//  missing list as empty (every collage saved before this existed).
//

import Foundation
import CoreGraphics

public struct CanvasDecoration: Codable, Sendable, Equatable {

    public enum Shape: String, Codable, Sendable {
        case rectangle
        case ellipse
    }

    /// Normalized (0…1) canvas rect.
    public var frame: CGRect
    public var shape: Shape
    /// "#RRGGBB" or "#RRGGBBAA" — tape and tinted panels are translucent.
    public var colorHex: String
    /// Corner radius as a fraction of the canvas's short side.
    public var cornerRadius: Double
    /// 0…1 soft drop shadow, the same strength scale as `FrameStyle.shadow`.
    public var shadow: Double

    public init(frame: CGRect, shape: Shape = .rectangle, colorHex: String = "#FFFFFF",
                cornerRadius: Double = 0, shadow: Double = 0) {
        self.frame = frame
        self.shape = shape
        self.colorHex = colorHex
        self.cornerRadius = cornerRadius
        self.shadow = shadow
    }

    private enum CodingKeys: String, CodingKey {
        case frame, shape, colorHex, color, cornerRadius, shadow
    }

    private struct UnitFrame: Codable {
        var x: Double = 0
        var y: Double = 0
        var width: Double = 0
        var height: Double = 0
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let raw = try c.decodeIfPresent(UnitFrame.self, forKey: .frame) ?? UnitFrame()
        // Clamped like a template cell: a decoration never spills off the canvas.
        let x = min(max(raw.x, 0), 1)
        let y = min(max(raw.y, 0), 1)
        frame = CGRect(x: x, y: y,
                       width: min(max(raw.width, 0), 1 - x),
                       height: min(max(raw.height, 0), 1 - y))
        shape = (try? c.decodeIfPresent(Shape.self, forKey: .shape)) ?? .rectangle
        // `color` is the template JSON's spelling (it matches text zones);
        // `colorHex` is what a saved project writes.
        colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex)
            ?? c.decodeIfPresent(String.self, forKey: .color) ?? "#FFFFFF"
        cornerRadius = max(0, try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0)
        shadow = min(max(try c.decodeIfPresent(Double.self, forKey: .shadow) ?? 0, 0), 1)
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(UnitFrame(x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                     forKey: .frame)
        try c.encode(shape, forKey: .shape)
        try c.encode(colorHex, forKey: .colorHex)
        try c.encode(cornerRadius, forKey: .cornerRadius)
        try c.encode(shadow, forKey: .shadow)
    }
}
