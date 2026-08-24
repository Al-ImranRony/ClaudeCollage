//
//  TextOverlay.swift
//  Caroullage
//
//  A text zone rendered on the collage canvas. Step 03a slice 5 turns these into
//  editable overlays layered on the grid/template editor.
//
//  Coordinate/size conventions (so the live canvas preview matches the export
//  pixel-for-pixel):
//   • `frame` is NORMALIZED (0…1) in canvas space — the same convention template
//     JSON uses. Each renderer multiplies it by its target canvas size.
//   • `fontSize` and `letterSpacing` are POINTS on the reference canvas (the app's
//     baseline pins a canvas's shorter side to 1080px, see CanvasSize). A renderer
//     drawing into a differently-scaled canvas multiplies them by
//     targetCanvas.height / referenceCanvas.height.
//   • `lineHeight` is a unitless multiple of the font's natural line height.
//

import Foundation
import CoreGraphics

public struct TextOverlay: Codable, Sendable, Equatable, Identifiable {

    public enum Alignment: String, Codable, Sendable, CaseIterable {
        case leading, center, trailing, justified
    }

    public var id: UUID
    public var text: String
    public var fontName: String
    public var fontSize: Double
    public var colorHex: String
    public var alignmentRaw: String
    public var letterSpacing: Double
    public var lineHeight: Double
    public var opacity: Double
    public var isBold: Bool
    public var isItalic: Bool
    public var isUnderlined: Bool
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double

    public init(
        id: UUID = UUID(),
        text: String = "",
        fontName: String = "SFProDisplay-Semibold",
        fontSize: Double = 64,
        colorHex: String = "#000000",
        alignment: Alignment = .center,
        letterSpacing: Double = 0,
        lineHeight: Double = 1.1,
        opacity: Double = 1,
        isBold: Bool = false,
        isItalic: Bool = false,
        isUnderlined: Bool = false,
        frame: CGRect = .zero
    ) {
        self.id = id
        self.text = text
        self.fontName = fontName
        self.fontSize = fontSize
        self.colorHex = colorHex
        self.alignmentRaw = alignment.rawValue
        self.letterSpacing = letterSpacing
        self.lineHeight = lineHeight
        self.opacity = opacity
        self.isBold = isBold
        self.isItalic = isItalic
        self.isUnderlined = isUnderlined
        self.frameX = Double(frame.origin.x)
        self.frameY = Double(frame.origin.y)
        self.frameWidth = Double(frame.size.width)
        self.frameHeight = Double(frame.size.height)
    }

    public var alignment: Alignment {
        get { Alignment(rawValue: alignmentRaw) ?? .center }
        set { alignmentRaw = newValue.rawValue }
    }

    public var frame: CGRect {
        get { CGRect(x: frameX, y: frameY, width: frameWidth, height: frameHeight) }
        set {
            frameX = Double(newValue.origin.x)
            frameY = Double(newValue.origin.y)
            frameWidth = Double(newValue.size.width)
            frameHeight = Double(newValue.size.height)
        }
    }

    // MARK: - Codable (defensive, forward-compatible)

    // Every field decodes with a fallback so a persisted overlay from an earlier
    // build (before bold/italic/underline existed) keeps loading, and a future
    // field addition never breaks an older snapshot. Mirrors the pattern used by
    // EditorCellState / GridEditorState.
    private enum CodingKeys: String, CodingKey {
        case id, text, fontName, fontSize, colorHex, alignmentRaw
        case letterSpacing, lineHeight, opacity, isBold, isItalic, isUnderlined
        case frameX, frameY, frameWidth, frameHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = TextOverlay()
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.text = try c.decodeIfPresent(String.self, forKey: .text) ?? fallback.text
        self.fontName = try c.decodeIfPresent(String.self, forKey: .fontName) ?? fallback.fontName
        self.fontSize = try c.decodeIfPresent(Double.self, forKey: .fontSize) ?? fallback.fontSize
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? fallback.colorHex
        self.alignmentRaw = try c.decodeIfPresent(String.self, forKey: .alignmentRaw) ?? fallback.alignmentRaw
        self.letterSpacing = try c.decodeIfPresent(Double.self, forKey: .letterSpacing) ?? fallback.letterSpacing
        self.lineHeight = try c.decodeIfPresent(Double.self, forKey: .lineHeight) ?? fallback.lineHeight
        self.opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity
        self.isBold = try c.decodeIfPresent(Bool.self, forKey: .isBold) ?? fallback.isBold
        self.isItalic = try c.decodeIfPresent(Bool.self, forKey: .isItalic) ?? fallback.isItalic
        self.isUnderlined = try c.decodeIfPresent(Bool.self, forKey: .isUnderlined) ?? fallback.isUnderlined
        self.frameX = try c.decodeIfPresent(Double.self, forKey: .frameX) ?? fallback.frameX
        self.frameY = try c.decodeIfPresent(Double.self, forKey: .frameY) ?? fallback.frameY
        self.frameWidth = try c.decodeIfPresent(Double.self, forKey: .frameWidth) ?? fallback.frameWidth
        self.frameHeight = try c.decodeIfPresent(Double.self, forKey: .frameHeight) ?? fallback.frameHeight
    }
}
