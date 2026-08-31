//
//  CarouselTemplateParser.swift
//  Caroullage
//
//  Step 03b slice 2 — a typed, defensive parser for the carousel template schema
//  (`Resources/CarouselTemplates/carousel_schema.json`). Mirrors the standard
//  `TemplateParser` contract exactly:
//   • `canvasAspectRatio` is the single hard requirement (a carousel with no canvas
//     is meaningless → throws); every other field degrades gracefully.
//   • Each frame's zones reuse the standard `TemplateCell` (the schema $refs the
//     template cell def), so photo/text/sticker zones parse identically and a
//     carousel frame maps straight onto a GridEditorState downstream.
//

import Foundation
import CoreGraphics

// MARK: - Model

public struct CarouselTemplate: Sendable, Equatable, Decodable {
    public let id: String
    public let name: String
    public let category: String
    public let isPremium: Bool
    public let carouselType: CarouselType
    public let canvasAspectRatio: String
    public let frameCount: Int
    public let frames: [CarouselTemplateFrame]
    /// Present only for panoramic carousels — how a wide source is sliced.
    public let panoramicSource: PanoramicSource?
    public let background: CollageBackground

    private enum CodingKeys: String, CodingKey {
        case id, name, category, isPremium, carouselType
        case canvasAspectRatio, frameCount, frames, panoramicSource, background
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // The one hard requirement.
        self.canvasAspectRatio = try c.decode(String.self, forKey: .canvasAspectRatio)
        self.id = try c.decodeIfPresent(String.self, forKey: .id) ?? "untitled"
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? "Untitled"
        self.category = try c.decodeIfPresent(String.self, forKey: .category) ?? "carousel"
        self.isPremium = try c.decodeIfPresent(Bool.self, forKey: .isPremium) ?? false
        // Unknown/absent type → matched (the most generic, always-valid layout).
        let rawType = try c.decodeIfPresent(String.self, forKey: .carouselType)
        self.carouselType = rawType.flatMap(CarouselType.init(rawValue:)) ?? .matched
        let parsedFrames = try c.decodeIfPresent([CarouselTemplateFrame].self, forKey: .frames) ?? []
        self.frames = parsedFrames
        // Absent frameCount falls back to the actual frame count, so it's never zero.
        self.frameCount = try c.decodeIfPresent(Int.self, forKey: .frameCount) ?? parsedFrames.count
        self.panoramicSource = try c.decodeIfPresent(PanoramicSource.self, forKey: .panoramicSource)
        self.background = (try? c.decodeIfPresent(TemplateBackground.self, forKey: .background))?
            .collageBackground ?? .white
    }
}

public struct CarouselTemplateFrame: Sendable, Equatable, Decodable {
    public let index: Int
    public let cells: [TemplateCell]

    private enum CodingKeys: String, CodingKey { case index, cells }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.index = try c.decodeIfPresent(Int.self, forKey: .index) ?? 0
        self.cells = try c.decodeIfPresent([TemplateCell].self, forKey: .cells) ?? []
    }
}

public struct PanoramicSource: Sendable, Equatable, Decodable {
    public let splitAxis: SplitAxis
    public let overlapPixels: Int

    private enum CodingKeys: String, CodingKey { case splitAxis, overlapPixels }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let rawAxis = try c.decodeIfPresent(String.self, forKey: .splitAxis)
        self.splitAxis = rawAxis.flatMap(SplitAxis.init(rawValue:)) ?? .horizontal
        self.overlapPixels = try c.decodeIfPresent(Int.self, forKey: .overlapPixels) ?? 0
    }
}

// MARK: - Parser

public enum CarouselTemplateParserError: Error, Equatable {
    case fileNotFound(String)
    case malformed(String)
}

public struct CarouselTemplateParser: Sendable {

    public init() {}

    /// Parses carousel template JSON into a typed `CarouselTemplate`.
    /// - Throws: `.malformed` when the hard-required `canvasAspectRatio` is absent.
    public func parse(data: Data) throws -> CarouselTemplate {
        do {
            return try JSONDecoder().decode(CarouselTemplate.self, from: data)
        } catch {
            throw CarouselTemplateParserError.malformed(String(describing: error))
        }
    }
}

// MARK: - Derived facts

public extension CarouselTemplate {

    /// Total `.photo` zones across every frame — "how many of your photos does
    /// this post need", which is the number the gallery card states next to the
    /// page count. Summed rather than per-frame: a grid-preview carousel opens
    /// with a 4-up frame and then shows each cell alone, so its per-frame count
    /// says nothing useful on its own.
    var photoZoneCount: Int {
        frames.reduce(0) { $0 + $1.cells.filter { $0.zoneType == .photo }.count }
    }
}
