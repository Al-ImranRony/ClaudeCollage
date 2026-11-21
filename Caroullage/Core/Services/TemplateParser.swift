//
//  TemplateParser.swift
//  Caroullage
//
//  Step 02 — a typed, defensive parser for the standard-template JSON schema
//  (`Resources/Templates/template_schema.json`). Introduced here because polygon
//  support needs to read each cell's `shape`; Step 03a builds the template
//  gallery on top of this model.
//
//  Design priority: never crash on bad data. `canvasAspectRatio` is the single
//  hard requirement (a template with no canvas is meaningless → throws). Every
//  other field degrades gracefully — unknown/missing `shape` becomes
//  `.rectangle`, out-of-range frame values are clamped to 0…1.
//

import Foundation
import CoreGraphics

// MARK: - Model

public struct CollageTemplate: Sendable, Equatable, Decodable {
    public let id: String
    public let name: String
    public let category: String
    public let isPremium: Bool
    public let canvasAspectRatio: String
    public let cells: [TemplateCell]
    public let background: CollageBackground
    /// Spacing, corner radius and frame chrome the editor opens with. `nil` for
    /// the legacy catalog, which keeps its original edge-to-edge previews and
    /// per-cell border seeding untouched.
    public let style: TemplateStyle?
    /// Cards, bands and tape under the photos — see `CanvasDecoration`.
    public let decorations: [CanvasDecoration]

    private enum CodingKeys: String, CodingKey {
        case id, name, category, isPremium, canvasAspectRatio, cells, background, style, decorations
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The one hard requirement.
        self.canvasAspectRatio = try c.decode(String.self, forKey: .canvasAspectRatio)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "untitled"
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        self.category = try c.decodeIfPresent(String.self, forKey: .category) ?? "grid"
        self.isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        self.cells = try c.decodeIfPresent([TemplateCell].self, forKey: .cells) ?? []
        self.background = (try? c.decodeIfPresent(TemplateBackground.self, forKey: .background))?
            .collageBackground ?? .white
        self.style = try? c.decodeIfPresent(TemplateStyle.self, forKey: .style)
        self.decorations = (try? c.decodeIfPresent([CanvasDecoration].self, forKey: .decorations)) ?? []
    }

    /// The number of photos the template asks for — what the gallery's photo
    /// filter and every card's caption state.
    public var photoCount: Int { cells.filter { $0.zoneType == .photo }.count }
}

/// A styled template's look, in reference-canvas points (short side 1080) —
/// exactly the units of the editor's Spacing, Corners and Frame controls, so a
/// template opens with those controls already where its preview left them.
///
/// With a style, a template's cell frames are authored EDGE TO EDGE (as tiles
/// of the canvas) and the spacing and margin carve the gaps, through the same
/// `CollageLayoutEngine` call the editor makes. That is what makes the preview
/// and the opened project the same picture rather than two approximations.
/// A template with decorations usually wants `spacing: 0` and no margin, so its
/// photos land exactly on the cards authored for them.
public struct TemplateStyle: Sendable, Equatable, Decodable {
    public let spacing: Double
    public let cornerRadius: Double
    public let frameStyle: FrameStyle

    private enum CodingKeys: String, CodingKey {
        case spacing, cornerRadius, outerMargin, shadow, outlineWidth, outlineHex
    }

    public init(spacing: Double = 0, cornerRadius: Double = 0, frameStyle: FrameStyle = FrameStyle()) {
        self.spacing = spacing
        self.cornerRadius = cornerRadius
        self.frameStyle = frameStyle
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        spacing = max(0, try c.decodeIfPresent(Double.self, forKey: .spacing) ?? 0)
        cornerRadius = max(0, try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0)
        frameStyle = FrameStyle(
            outerMargin: try c.decodeIfPresent(Double.self, forKey: .outerMargin).map { max(0, $0) },
            shadow: min(max(try c.decodeIfPresent(Double.self, forKey: .shadow) ?? 0, 0), 1),
            outlineWidth: max(0, try c.decodeIfPresent(Double.self, forKey: .outlineWidth) ?? 0),
            outlineHex: try c.decodeIfPresent(String.self, forKey: .outlineHex) ?? "#FFFFFF")
    }
}

/// The role a template cell plays. Step 02 templates were all `.photo`; Step 03a
/// introduces text/sticker/art/spacer zones. Unknown/missing → `.photo` so older
/// and malformed templates keep loading.
public enum TemplateZoneType: String, Sendable, Equatable, Codable, CaseIterable {
    case photo
    case text
    case sticker
    case art          // decorative, non-interactive artwork baked from the template
    case spacer       // empty padding

    public init(raw: String?) {
        self = raw.flatMap(TemplateZoneType.init(rawValue:)) ?? .photo
    }
}

public struct TemplateCell: Sendable, Equatable, Decodable {
    public let id: String
    public let type: String
    public let zoneType: TemplateZoneType
    public let frame: CGRect        // clamped to the unit square
    public let shape: CellShape     // `.rectangle` when missing/unknown
    public let borderWidth: Double
    public let cornerRadius: Double
    /// Present only for `.text` zones — the default styling + placeholder string
    /// the editor seeds when the user first taps the zone.
    public let textStyle: TextOverlay?
    /// Present only for `.sticker` zones — the bundled sticker id to preload, if any.
    public let stickerID: String?

    private enum CodingKeys: String, CodingKey {
        case id, type, frame, shape, borderWidth, cornerRadius
        case text, fontName, fontSize, color, alignment, stickerID
        case letterSpacing, lineHeight
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "photo"
        self.zoneType = TemplateZoneType(raw: self.type)

        let rawFrame = try c.decodeIfPresent(TemplateFrame.self, forKey: .frame) ?? TemplateFrame()
        self.frame = rawFrame.clampedRect

        // Unknown or absent shape strings degrade to `.rectangle` — never throws.
        let rawShape = try c.decodeIfPresent(String.self, forKey: .shape)
        self.shape = rawShape.flatMap(CellShape.init(rawValue:)) ?? .rectangle

        self.borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
        self.cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0

        // Text zones seed a `TextOverlay`. Any styling fields present in the JSON
        // override the sensible defaults; absent fields fall back gracefully. The
        // zone's normalized `frame` becomes the overlay frame.
        if self.zoneType == .text {
            let alignment = (try c.decodeIfPresent(String.self, forKey: .alignment))
                .flatMap(TextOverlay.Alignment.init(rawValue:)) ?? .center
            var overlay = TextOverlay(
                text: (try? c.decodeIfPresent(String.self, forKey: .text)) ?? "",
                alignment: alignment,
                frame: self.frame
            )
            if let fontName = try? c.decodeIfPresent(String.self, forKey: .fontName) {
                overlay.fontName = fontName
            }
            if let fontSize = try? c.decodeIfPresent(Double.self, forKey: .fontSize) {
                overlay.fontSize = fontSize
            }
            if let color = try? c.decodeIfPresent(String.self, forKey: .color) {
                overlay.colorHex = color
            }
            // Tracking and leading are what separate an editorial caption from a
            // label — small tracked capitals ("VOL. 01") read as design, the
            // same string untracked reads as a placeholder.
            if let spacing = try? c.decodeIfPresent(Double.self, forKey: .letterSpacing) {
                overlay.letterSpacing = spacing
            }
            if let leading = try? c.decodeIfPresent(Double.self, forKey: .lineHeight), leading > 0 {
                overlay.lineHeight = leading
            }
            self.textStyle = overlay
        } else {
            self.textStyle = nil
        }

        self.stickerID = self.zoneType == .sticker
            ? (try? c.decodeIfPresent(String.self, forKey: .stickerID)) ?? nil
            : nil
    }
}

// MARK: - Raw JSON sub-objects

private struct TemplateFrame: Decodable {
    var x: Double = 0
    var y: Double = 0
    var width: Double = 1
    var height: Double = 1

    /// Clamps origin to 0…1 and size so the cell never spills past the canvas.
    var clampedRect: CGRect {
        let cx = min(max(x, 0), 1)
        let cy = min(max(y, 0), 1)
        let cw = min(max(width, 0), 1 - cx)
        let ch = min(max(height, 0), 1 - cy)
        return CGRect(x: cx, y: cy, width: cw, height: ch)
    }
}

// Internal (not private): the carousel template parser reuses this same solid/
// gradient → CollageBackground mapping so both catalogs decode backgrounds identically.
struct TemplateBackground: Decodable {
    let type: String
    let color: String?
    let colors: [String]?

    let angle: Double?
    /// `pattern` only: which motif, drawn in `ink` over `paper`.
    let pattern: String?
    let ink: String?
    let paper: String?
    /// `photoBlur` only: how far the blurred backdrop is darkened, 0…1.
    let dim: Double?

    /// Maps to the app's `CollageBackground`. A gradient with fewer than two
    /// stops has nothing to blend, so it falls back to a solid of its one colour.
    /// An unknown pattern name degrades to its paper colour rather than failing
    /// the whole template.
    var collageBackground: CollageBackground {
        if type == "solid", let color { return .solid(hex: color) }
        if type == "gradient", let colors, colors.count >= 2 {
            return .gradient(colors: colors, angle: angle ?? 0)
        }
        if type == "pattern" {
            let paperHex = paper ?? color ?? "#FFFFFF"
            guard let kind = pattern.flatMap(BackgroundPattern.init(rawValue:)) else {
                return .solid(hex: paperHex)
            }
            return .pattern(kind, ink: ink ?? "#000000", paper: paperHex)
        }
        if type == "photoBlur" { return .photoBlur(dim: min(max(dim ?? 0.2, 0), 1)) }
        if let first = colors?.first { return .solid(hex: first) }
        return .white
    }
}

// MARK: - Parser

public enum TemplateParserError: Error, Equatable {
    case fileNotFound(String)
    case malformed(String)
}

public struct TemplateParser: Sendable {

    public init() {}

    /// Parses template JSON data into a typed `CollageTemplate`.
    /// - Throws: `TemplateParserError.malformed` if required fields are absent.
    public func parse(data: Data) throws -> CollageTemplate {
        do {
            return try JSONDecoder().decode(CollageTemplate.self, from: data)
        } catch {
            throw TemplateParserError.malformed(String(describing: error))
        }
    }

    /// Loads a named template JSON from the given bundle.
    public func parseTemplate(named name: String, in bundle: Bundle = .main) throws -> CollageTemplate {
        guard let url = bundle.url(forResource: name, withExtension: "json", subdirectory: "Templates")
            ?? bundle.url(forResource: name, withExtension: "json") else {
            throw TemplateParserError.fileNotFound(name)
        }
        return try parse(data: try Data(contentsOf: url))
    }
}
