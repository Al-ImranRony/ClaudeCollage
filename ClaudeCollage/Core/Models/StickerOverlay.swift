//
//  StickerOverlay.swift
//  ClaudeCollage
//
//  Step 03a slice 6 — a sticker placed freely on the collage canvas. Like
//  `TextOverlay`, a sticker is an editor overlay layered above the photo cells and
//  carried inside `GridEditorState`, so adding / moving / resizing / rotating one
//  rides the existing undo-redo + autosave with no new persistence machinery.
//
//  Coordinate conventions (so the live canvas preview matches the export exactly):
//   • `center` is NORMALIZED (0…1) in canvas space — x is a fraction of the canvas
//     width, y of its height.
//   • `sizeNorm` is the sticker's SQUARE box side as a fraction of the canvas
//     WIDTH, so a sticker keeps its on-screen proportions on any canvas ratio.
//   • `rotation` is in radians, applied around the box centre.
//
//  A sticker resolves to an SF Symbol (`symbolName`). The picker/template seed
//  stores the concrete symbol name on the overlay so both renderers (live canvas
//  UIImageView + Core Graphics export) draw it without needing the sticker catalog
//  — the same "one source of truth, preview == export" rule slice 5 used for text.
//

import CoreGraphics
import Foundation

public struct StickerOverlay: Codable, Sendable, Equatable, Identifiable {

    public var id: UUID
    /// The catalog id that produced this sticker ("<pack>.<name>"), kept for
    /// reference/analytics. Rendering uses `symbolName`, not this.
    public var stickerID: String
    /// The concrete SF Symbol the sticker draws.
    public var symbolName: String
    public var colorHex: String
    public var opacity: Double
    public var centerX: Double
    public var centerY: Double
    public var sizeNorm: Double
    public var rotation: Double

    public init(
        id: UUID = UUID(),
        stickerID: String = "",
        symbolName: String = "star.fill",
        colorHex: String = "#E86A2A",
        opacity: Double = 1,
        center: CGPoint = CGPoint(x: 0.5, y: 0.5),
        sizeNorm: Double = 0.28,
        rotation: Double = 0
    ) {
        self.id = id
        self.stickerID = stickerID
        self.symbolName = symbolName
        self.colorHex = colorHex
        self.opacity = opacity
        self.centerX = Double(center.x)
        self.centerY = Double(center.y)
        self.sizeNorm = sizeNorm
        self.rotation = rotation
    }

    public var center: CGPoint {
        get { CGPoint(x: centerX, y: centerY) }
        set { centerX = Double(newValue.x); centerY = Double(newValue.y) }
    }

    // MARK: - Codable (defensive, forward-compatible)

    // Every field decodes with a fallback so a persisted overlay from an earlier
    // build keeps loading and a future field addition never breaks an older
    // snapshot — mirrors TextOverlay / EditorCellState.
    private enum CodingKeys: String, CodingKey {
        case id, stickerID, symbolName, colorHex, opacity
        case centerX, centerY, sizeNorm, rotation
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = StickerOverlay()
        self.id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        self.stickerID = try c.decodeIfPresent(String.self, forKey: .stickerID) ?? fallback.stickerID
        self.symbolName = try c.decodeIfPresent(String.self, forKey: .symbolName) ?? fallback.symbolName
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .colorHex) ?? fallback.colorHex
        self.opacity = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? fallback.opacity
        self.centerX = try c.decodeIfPresent(Double.self, forKey: .centerX) ?? fallback.centerX
        self.centerY = try c.decodeIfPresent(Double.self, forKey: .centerY) ?? fallback.centerY
        self.sizeNorm = try c.decodeIfPresent(Double.self, forKey: .sizeNorm) ?? fallback.sizeNorm
        self.rotation = try c.decodeIfPresent(Double.self, forKey: .rotation) ?? fallback.rotation
    }
}
