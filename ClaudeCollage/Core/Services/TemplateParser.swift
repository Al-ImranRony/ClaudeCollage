//
//  TemplateParser.swift
//  ClaudeCollage
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

    private enum CodingKeys: String, CodingKey {
        case id, name, category, isPremium, canvasAspectRatio, cells, background
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
    }
}

public struct TemplateCell: Sendable, Equatable, Decodable {
    public let id: String
    public let type: String
    public let frame: CGRect        // clamped to the unit square
    public let shape: CellShape     // `.rectangle` when missing/unknown
    public let borderWidth: Double
    public let cornerRadius: Double

    private enum CodingKeys: String, CodingKey {
        case id, type, frame, shape, borderWidth, cornerRadius
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        self.type = try c.decodeIfPresent(String.self, forKey: .type) ?? "photo"

        let rawFrame = try c.decodeIfPresent(TemplateFrame.self, forKey: .frame) ?? TemplateFrame()
        self.frame = rawFrame.clampedRect

        // Unknown or absent shape strings degrade to `.rectangle` — never throws.
        let rawShape = try c.decodeIfPresent(String.self, forKey: .shape)
        self.shape = rawShape.flatMap(CellShape.init(rawValue:)) ?? .rectangle

        self.borderWidth = try c.decodeIfPresent(Double.self, forKey: .borderWidth) ?? 0
        self.cornerRadius = try c.decodeIfPresent(Double.self, forKey: .cornerRadius) ?? 0
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

private struct TemplateBackground: Decodable {
    let type: String
    let color: String?
    let colors: [String]?

    /// Maps to the app's `CollageBackground` (solid only in v1; gradients arrive
    /// with the template system in Step 03).
    var collageBackground: CollageBackground {
        if type == "solid", let color { return .solid(hex: color) }
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
