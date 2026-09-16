//
//  SuggestionPreviewCache.swift
//  Caroullage
//
//  Home retention, phase 2 — "From your photos", rendered rather than drawn.
//
//  Home's suggestions used to show `LayoutSchematicCell` wireframes: grey wells
//  on a screen whose whole premise is photo-real output, under a header that
//  promised a collage made from the user's own photos. This renders exactly
//  that — the user's recent photos composited into each suggested layout,
//  through the same `GridEditorViewModel` → `CollageRenderer` path the editor
//  will use when the card is tapped, so the thumbnail IS what opens.
//
//  Two caches, both keyed on the photo library's contents (the asset ids in
//  order) rather than on time: the suggested layouts themselves, which cost a
//  Vision pass per photo, and the composited thumbnails, which are memory plus
//  small PNGs under Caches so a relaunch does not re-render either. Renders
//  run detached — `RenderRequest` is `Sendable`, `CollageRenderer` is
//  `@unchecked Sendable` — so Home never hitches on one, and one render per key
//  is ever in flight.
//

import Foundation
import UIKit

/// One suggestion: the layout, and the user's photos already in it.
public struct HomeSuggestion: Sendable {
    public let template: GridTemplate
    /// Nil only while the render is still in flight or has failed; the cell
    /// then shows the well it would have shown anyway.
    public let thumbnail: CGImage?

    public init(template: GridTemplate, thumbnail: CGImage?) {
        self.template = template
        self.thumbnail = thumbnail
    }
}

@MainActor
public final class SuggestionPreviewCache {

    /// How many thumbnails the disk cache keeps. Three per library state, so
    /// this holds the last few states and nothing older.
    static let diskCapacity = 12

    private let renderer: CollageRenderer
    private let maxDimension: CGFloat
    private let directory: URL?

    private var thumbnails: [String: CGImage] = [:]
    private var renders: [String: Task<CGImage?, Never>] = [:]
    private var layouts: [String: [GridTemplate]] = [:]

    /// How many renders actually ran. Tests read it to prove the caches hit.
    public private(set) var renderCount = 0

    public init(
        renderer: CollageRenderer = CollageRenderer(),
        maxDimension: CGFloat = 300,
        directory: URL? = SuggestionPreviewCache.defaultDirectory()
    ) {
        self.renderer = renderer
        self.maxDimension = maxDimension
        self.directory = directory
        if let directory {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
    }

    public static func defaultDirectory() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent("SuggestionThumbnails", isDirectory: true)
    }

    // MARK: - Suggested layouts

    /// The layouts last suggested for exactly these photos, if the library has
    /// not changed since. Skips the Vision pass on every Home appearance.
    public func cachedLayouts(forAssetIDs ids: [String]) -> [GridTemplate]? {
        layouts[Self.assetKey(ids)]
    }

    public func store(layouts templates: [GridTemplate], forAssetIDs ids: [String]) {
        layouts = [Self.assetKey(ids): templates]   // one library state at a time
    }

    // MARK: - Thumbnails

    /// A thumbnail already on hand for these assets, without any photo to
    /// render from — memory or disk. What lets Home skip decoding the library
    /// entirely when nothing in it has changed.
    public func cachedThumbnail(for template: GridTemplate, assetIDs: [String]) -> CGImage? {
        let key = thumbnailKey(template: template, assetIDs: Array(assetIDs.prefix(template.cellCount)))
        if let cached = thumbnails[key] { return cached }
        guard let onDisk = loadFromDisk(key) else { return nil }
        thumbnails[key] = onDisk
        return onDisk
    }

    /// The user's photos composited into `template`, at `maxDimension`.
    ///
    /// Memory, then disk, then a detached render. A second call for the same
    /// key while a render is in flight awaits that render rather than starting
    /// another.
    public func thumbnail(for template: GridTemplate, photos: [RecentPhoto]) async -> CGImage? {
        let used = Array(photos.prefix(template.cellCount))
        let key = thumbnailKey(template: template, assetIDs: used.map(\.assetID))

        if let cached = thumbnails[key] { return cached }
        if let onDisk = loadFromDisk(key) {
            thumbnails[key] = onDisk
            return onDisk
        }
        if let running = renders[key] { return await running.value }

        // Built on the actor: it is what the editor would build for a tap on
        // this card, which is the point. Rendered off it.
        let viewModel = GridEditorViewModel(state: GridEditorState(template: template))
        for (index, photo) in used.enumerated() {
            viewModel.setImage(photo.image, forCellAt: index)
        }
        let request = viewModel.renderRequestSnapshot()
        let scale = viewModel.thumbnailScale(maxDimension: maxDimension)
        let renderer = self.renderer
        renderCount += 1

        let task = Task.detached(priority: .utility) { () -> CGImage? in
            renderer.render(request, scale: scale)
        }
        renders[key] = task
        let rendered = await task.value
        renders[key] = nil

        if let rendered {
            thumbnails[key] = rendered
            storeToDisk(rendered, key: key)
        }
        return rendered
    }

    /// Everything, so a test — or a user revoking photo access — leaves no
    /// composite of their photos behind.
    public func removeAll() {
        thumbnails.removeAll()
        layouts.removeAll()
        guard let directory else { return }
        try? FileManager.default.removeItem(at: directory)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    // MARK: - Keys

    private static func assetKey(_ ids: [String]) -> String {
        ids.joined(separator: "|")
    }

    private func thumbnailKey(template: GridTemplate, assetIDs: [String]) -> String {
        "\(template.rawValue)|\(Self.assetKey(assetIDs))@\(Int(maxDimension))-r\(TemplateService.rendererRevision)"
    }

    // MARK: - Disk

    private func fileURL(for key: String) -> URL? {
        // Asset identifiers carry slashes; the key is hashed into a file name.
        var hasher = Hasher()
        hasher.combine(key)
        let name = String(UInt(bitPattern: hasher.finalize()), radix: 36)
        return directory?.appendingPathComponent("\(name).png")
    }

    private func loadFromDisk(_ key: String) -> CGImage? {
        guard let url = fileURL(for: key),
              let image = UIImage(contentsOfFile: url.path)?.cgImage else { return nil }
        return image
    }

    private func storeToDisk(_ image: CGImage, key: String) {
        guard let url = fileURL(for: key), directory != nil else { return }
        try? UIImage(cgImage: image).pngData()?.write(to: url, options: .atomic)
        var order = diskOrder.filter { $0 != url.lastPathComponent }
        order.append(url.lastPathComponent)
        // Oldest first, down to `diskCapacity`. Ordered by our own index rather
        // than by file dates: reading a modification date is a required-reason
        // API the privacy manifest would have to declare, for no gain.
        while order.count > Self.diskCapacity, let oldest = order.first {
            order.removeFirst()
            if let directory { try? FileManager.default.removeItem(at: directory.appendingPathComponent(oldest)) }
        }
        diskOrder = order
    }

    private var indexURL: URL? { directory?.appendingPathComponent("index.json") }

    /// File names in the order they were written.
    private var diskOrder: [String] {
        get {
            guard let indexURL, let data = try? Data(contentsOf: indexURL),
                  let names = try? JSONDecoder().decode([String].self, from: data) else { return [] }
            return names
        }
        set {
            guard let indexURL, let data = try? JSONEncoder().encode(newValue) else { return }
            try? data.write(to: indexURL, options: .atomic)
        }
    }
}
