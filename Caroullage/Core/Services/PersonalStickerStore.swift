//
//  PersonalStickerStore.swift
//  Caroullage
//
//  Step 05 batch B — CRUD plus an in-memory bitmap cache for personal stickers.
//
//  Holds the `ModelContainer` strongly: a container released while a context is
//  alive traps on the next fetch (see the SwiftData retention note this project
//  hit back in Step 01), so every store here owns its container.
//
//  Decoded `CGImage`s are cached because both renderers ask for them constantly —
//  the live canvas on every sticker layout pass, the exporter on every render —
//  and decoding a PNG each time would undo the whole point of the geometry-only
//  canvas path added in Step 04.5.
//

import CoreGraphics
import Foundation
import SwiftData
import UIKit

@MainActor
public final class PersonalStickerStore {

    private let container: ModelContainer
    private lazy var context = ModelContext(container)
    private var imageCache: [UUID: CGImage] = [:]

    public init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Reading

    /// Newest first — a sticker just lifted should be the first one offered.
    public func allStickers() -> [PersonalSticker] {
        let descriptor = FetchDescriptor<PersonalSticker>(
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)])
        return (try? context.fetch(descriptor)) ?? []
    }

    public func isEmpty() -> Bool { allStickers().isEmpty }

    /// Decoded bitmap for one sticker, or nil if it is unknown or unreadable.
    public func image(for id: UUID) -> CGImage? {
        if let cached = imageCache[id] { return cached }
        let target = FetchDescriptor<PersonalSticker>(
            predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(target).first,
              let decoded = UIImage(data: record.imageData)?.cgImage else { return nil }
        imageCache[id] = decoded
        return decoded
    }

    /// Bitmaps for the personal stickers referenced by these overlays.
    ///
    /// The renderers need a plain dictionary they can carry across actors, so the
    /// resolution happens here rather than as a lookup deep in a draw call.
    public func images(for overlays: [StickerOverlay]) -> [UUID: CGImage] {
        var resolved: [UUID: CGImage] = [:]
        for id in Set(overlays.compactMap(\.imageID)) {
            resolved[id] = image(for: id)
        }
        return resolved
    }

    // MARK: - Writing

    /// Saves a lifted subject as a reusable sticker and returns its id.
    ///
    /// PNG, not JPEG: the subject's alpha is the entire point of it.
    @discardableResult
    public func save(_ image: CGImage) -> UUID? {
        guard let data = UIImage(cgImage: image).pngData() else { return nil }
        let sticker = PersonalSticker(imageData: data)
        context.insert(sticker)
        try? context.save()
        imageCache[sticker.id] = image
        return sticker.id
    }

    public func delete(id: UUID) {
        let target = FetchDescriptor<PersonalSticker>(predicate: #Predicate { $0.id == id })
        guard let record = try? context.fetch(target).first else { return }
        context.delete(record)
        try? context.save()
        imageCache[id] = nil
    }
}
