//
//  StickerCatalog.swift
//  Caroullage
//
//  Step 03a slice 6 — loads the bundled sticker packs from `Resources/Stickers/`
//  and answers "what symbol/colour does this sticker id resolve to?". The picker
//  reads `packs` to build its grid; `AppCoordinator` uses `entry(for:)` to seed a
//  template's sticker zones into concrete overlays.
//
//  Each pack is a small JSON manifest describing SF-Symbol-backed stickers (see
//  the slice-6 deviation note in StickerRendering) — parsing is defensive: a
//  malformed pack is skipped, a malformed sticker within a pack is dropped, and
//  the app still launches with whatever parsed.
//

import Foundation

/// One sticker in a pack: a stable id, the SF Symbol it draws, a display name, and
/// its default tint.
public struct StickerEntry: Sendable, Equatable, Decodable, Identifiable {
    public let id: String          // "<pack>.<name>"
    public let symbol: String      // SF Symbol name
    public let name: String
    public let colorHex: String

    private enum CodingKeys: String, CodingKey {
        case id, symbol, name, color
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.symbol = try c.decode(String.self, forKey: .symbol)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? id
        self.colorHex = try c.decodeIfPresent(String.self, forKey: .color) ?? "#E86A2A"
    }

    public init(id: String, symbol: String, name: String, colorHex: String) {
        self.id = id
        self.symbol = symbol
        self.name = name
        self.colorHex = colorHex
    }
}

/// A themed group of stickers, shown as one tab in the picker.
public struct StickerPack: Sendable, Equatable, Decodable, Identifiable {
    public let id: String
    public let name: String
    public let symbol: String      // the pack's tab glyph
    public let stickers: [StickerEntry]

    private enum CodingKeys: String, CodingKey {
        case id, name, symbol, stickers
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        self.id = try c.decode(String.self, forKey: .id)
        self.name = try c.decodeIfPresent(String.self, forKey: .name) ?? id.capitalized
        self.symbol = try c.decodeIfPresent(String.self, forKey: .symbol) ?? "face.smiling"
        self.stickers = try c.decodeIfPresent([StickerEntry].self, forKey: .stickers) ?? []
    }
}

@MainActor
public final class StickerCatalog {

    public static let shared = StickerCatalog()

    private let bundle: Bundle
    /// Stable pack order (matches the picker's tab order).
    private static let packOrder = ["basic", "nature", "celebration"]

    public private(set) var packs: [StickerPack] = []
    private var entriesByID: [String: StickerEntry] = [:]

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
    }

    // MARK: - Loading

    /// Parses every sticker pack JSON in the bundle. Idempotent — safe to call at
    /// launch or lazily before showing the picker. Packs are ordered by the known
    /// order first, then alphabetically for any extras.
    @discardableResult
    public func loadPacks() -> [StickerPack] {
        guard packs.isEmpty else { return packs }
        let parsed: [StickerPack] = packURLs().compactMap { url in
            guard let data = try? Data(contentsOf: url),
                  let pack = try? JSONDecoder().decode(StickerPack.self, from: data),
                  !pack.stickers.isEmpty else { return nil }
            return pack
        }
        packs = parsed.sorted { lhs, rhs in
            let li = Self.packOrder.firstIndex(of: lhs.id) ?? Int.max
            let ri = Self.packOrder.firstIndex(of: rhs.id) ?? Int.max
            return li == ri ? lhs.name < rhs.name : li < ri
        }
        entriesByID = Dictionary(
            packs.flatMap(\.stickers).map { ($0.id, $0) },
            uniquingKeysWith: { first, _ in first }
        )
        return packs
    }

    /// Looks up a sticker by its catalog id ("<pack>.<name>").
    public func entry(for id: String) -> StickerEntry? {
        if entriesByID.isEmpty { loadPacks() }
        return entriesByID[id]
    }

    // MARK: - Bundle scanning

    private func packURLs() -> [URL] {
        if let inSubdir = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Stickers"),
           !inSubdir.isEmpty {
            return inSubdir
        }
        // Flat-bundle fallback: match the pack_* naming convention.
        let all = bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
        return all.filter { $0.lastPathComponent.hasPrefix("pack_") }
    }
}
