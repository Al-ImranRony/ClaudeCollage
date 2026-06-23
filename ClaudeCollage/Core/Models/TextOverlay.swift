//
//  TextOverlay.swift
//  ClaudeCollage
//
//  Per-cell text overlay value type. Stub for Step 00.
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
    public var frameX: Double
    public var frameY: Double
    public var frameWidth: Double
    public var frameHeight: Double

    public init(
        id: UUID = UUID(),
        text: String = "",
        fontName: String = "SFProDisplay-Regular",
        fontSize: Double = 18,
        colorHex: String = "#000000",
        alignment: Alignment = .center,
        letterSpacing: Double = 0,
        lineHeight: Double = 1.2,
        opacity: Double = 1,
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
}
