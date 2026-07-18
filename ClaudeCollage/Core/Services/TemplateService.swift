//
//  TemplateService.swift
//  ClaudeCollage
//
//  Step 03a — loads the bundled template catalog, renders + caches gallery
//  thumbnails, and answers premium-gating questions. Built on the Step 02
//  `TemplateParser` (parsing) and the Step 01 `CollageRenderer` (thumbnails), so
//  no layout or rendering code is duplicated here.
//
//  Premium templates: `isPremium(_:)` reports the flag; `canOpen(_:)` layers the
//  live entitlement on top (free users are blocked until they unlock premium —
//  real StoreKit arrives in Step 06, `EntitlementStore` stands in until then).
//

import CoreGraphics
import Foundation
import UIKit

@MainActor
public final class TemplateService {

    public static let shared = TemplateService()

    private let bundle: Bundle
    private let parser = TemplateParser()
    private let carouselParser = CarouselTemplateParser()
    private let renderer = CollageRenderer()
    private let entitlements: EntitlementStore

    /// All successfully-parsed bundled templates, populated by `loadBundledTemplates()`.
    public private(set) var templates: [CollageTemplate] = []

    /// All successfully-parsed bundled carousel templates (Step 03b), populated by
    /// `loadBundledCarouselTemplates()`. Kept separate from `templates` — carousel
    /// templates live in their own bundle subdirectory and drive the carousel editor,
    /// not the standard gallery.
    public private(set) var carouselTemplates: [CarouselTemplate] = []

    /// In-memory thumbnail cache, backed by an on-disk PNG cache that survives
    /// relaunches.
    private var thumbnailCache: [String: CGImage] = [:]

    public init(bundle: Bundle = .main, entitlements: EntitlementStore = .shared) {
        self.bundle = bundle
        self.entitlements = entitlements
    }

    // MARK: - Loading

    /// Parses every template JSON in the bundle (skipping the schema and any file
    /// that isn't a valid template). Idempotent — safe to call at launch. Results
    /// are sorted premium-last, then by name, for a stable gallery order.
    @discardableResult
    public func loadBundledTemplates() -> [CollageTemplate] {
        let urls = bundledTemplateURLs()
        let parsed: [CollageTemplate] = urls.compactMap { url in
            // Skip the JSON schema and any carousel template. Carousel JSONs also
            // carry a top-level `canvasAspectRatio`, so without this they'd parse as
            // empty standard templates and pollute the gallery (resources are
            // flattened into the bundle root, so the two catalogs are told apart by
            // the `carousel` filename prefix, not by subdirectory).
            let name = url.lastPathComponent
            guard name != "template_schema.json",
                  !name.hasPrefix("carousel"),
                  let data = try? Data(contentsOf: url),
                  let template = try? parser.parse(data: data) else { return nil }
            return template
        }
        templates = parsed.sorted {
            $0.isPremium == $1.isPremium ? $0.name < $1.name : (!$0.isPremium && $1.isPremium)
        }
        return templates
    }

    /// Parses every carousel template JSON in the `CarouselTemplates` subdirectory
    /// (skipping the schema and anything that fails to parse). Idempotent. Sorted
    /// premium-last, then by name, matching the standard catalog's stable order.
    @discardableResult
    public func loadBundledCarouselTemplates() -> [CarouselTemplate] {
        // Prefer a real CarouselTemplates subdirectory if the bundle ever preserves
        // one; today resources flatten into the root, so fall back there and select
        // by the `carousel` filename prefix (the schema, `carousel_schema.json`, is
        // excluded explicitly).
        let subdirURLs = bundle.urls(forResourcesWithExtension: "json", subdirectory: "CarouselTemplates")
        let urls = (subdirURLs?.isEmpty == false ? subdirURLs : nil)
            ?? bundle.urls(forResourcesWithExtension: "json", subdirectory: nil)
            ?? []
        let parsed: [CarouselTemplate] = urls.compactMap { url in
            let name = url.lastPathComponent
            guard name.hasPrefix("carousel"), name != "carousel_schema.json",
                  let data = try? Data(contentsOf: url),
                  let template = try? carouselParser.parse(data: data) else { return nil }
            return template
        }
        carouselTemplates = parsed.sorted {
            $0.isPremium == $1.isPremium ? $0.name < $1.name : (!$0.isPremium && $1.isPremium)
        }
        return carouselTemplates
    }

    /// Templates matching a category ("All" / empty returns everything).
    public func templates(inCategory category: String?) -> [CollageTemplate] {
        guard let category, !category.isEmpty, category.lowercased() != "all" else { return templates }
        return templates.filter { $0.category.caseInsensitiveCompare(category) == .orderedSame }
    }

    /// Templates whose authored aspect ratio matches the chosen canvas preset.
    public func templates(forCanvas preset: CanvasPreset) -> [CollageTemplate] {
        templates.filter {
            CanvasSize.normalize($0.canvasAspectRatio) == CanvasSize.normalize(preset.aspectRatio)
        }
    }

    // MARK: - Premium gating

    /// Whether the template itself is marked premium in its JSON.
    public func isPremium(_ template: CollageTemplate) -> Bool { template.isPremium }

    /// Whether the current user may open the template: free templates always, and
    /// premium templates only once the entitlement is unlocked.
    public func canOpen(_ template: CollageTemplate) -> Bool {
        !template.isPremium || entitlements.isPremiumUnlocked
    }

    // MARK: - Thumbnails

    /// A `maxDimension`-bounded thumbnail for the template, rendered once via the
    /// shared `CollageRenderer` and cached in memory + on disk. Photo zones show
    /// the empty-cell placeholder (there is no user imagery yet).
    public func thumbnail(for template: CollageTemplate, maxDimension: CGFloat = 300) -> CGImage? {
        // The key carries a content fingerprint so a re-authored template (same
        // id, new geometry/background) never serves its stale cached thumbnail.
        let key = "\(template.id)-\(Self.contentFingerprint(of: template))@\(Int(maxDimension))"
        if let cached = thumbnailCache[key] { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache[key] = disk
            return disk
        }
        guard let image = renderer.render(renderRequest(for: template, maxDimension: maxDimension), scale: 1) else {
            return nil
        }
        thumbnailCache[key] = image
        storeDiskThumbnail(image, key: key)
        return image
    }

    // MARK: - Template → render request

    /// Builds a `RenderRequest` for the template fitted into a `maxDimension` box
    /// (longest side = `maxDimension`), preserving the authored aspect ratio.
    /// Photo / art zones become render cells; text zones render as overlays so the
    /// gallery thumbnail previews the template's typography. Sticker and spacer
    /// zones remain purely interactive and are omitted.
    public func renderRequest(for template: CollageTemplate, maxDimension: CGFloat = 300) -> RenderRequest {
        let native = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
        let longest = max(native.width, native.height, 1)
        let scale = maxDimension / longest
        let canvas = CGSize(width: (native.width * scale).rounded(),
                            height: (native.height * scale).rounded())

        let cells: [RenderCell] = template.cells
            .filter { $0.zoneType == .photo || $0.zoneType == .art }
            .map { cell in
                let absolute = CGRect(
                    x: cell.frame.origin.x * canvas.width,
                    y: cell.frame.origin.y * canvas.height,
                    width: cell.frame.size.width * canvas.width,
                    height: cell.frame.size.height * canvas.height
                )
                return RenderCell(
                    frame: absolute,
                    image: nil,
                    transform: CellTransform(panX: 0, panY: 0, zoom: 1, rotationRadians: 0),
                    cornerRadius: CGFloat(cell.cornerRadius) * min(canvas.width, canvas.height),
                    clipShape: Self.clipShape(for: cell.shape)
                )
            }

        // The thumbnail canvas is `native × scale`, so the overlays' reference-canvas
        // point sizes scale by the same factor.
        let textOverlays = template.cells.compactMap(\.textStyle)

        return RenderRequest(canvasSize: canvas, background: template.background,
                             cells: cells, textOverlays: textOverlays, textFontScale: scale,
                             stickerOverlays: Self.stickerOverlays(for: template))
    }

    // MARK: - Sticker seeding

    /// Resolves a template's sticker zones into concrete `StickerOverlay`s (symbol +
    /// colour from the sticker catalog, geometry from the zone frame). Used to seed
    /// the editor and to preview stickers in gallery thumbnails.
    public static func stickerOverlays(for template: CollageTemplate) -> [StickerOverlay] {
        template.cells.compactMap { cell in
            guard cell.zoneType == .sticker, let id = cell.stickerID else { return nil }
            let entry = StickerCatalog.shared.entry(for: id)
            // Size uses the zone width as a fraction of the canvas width (stickers
            // are square in pixels — see StickerOverlay).
            return StickerOverlay(
                stickerID: id,
                symbolName: entry?.symbol ?? "star.fill",
                colorHex: entry?.colorHex ?? "#E86A2A",
                center: CGPoint(x: cell.frame.midX, y: cell.frame.midY),
                sizeNorm: Double(cell.frame.width)
            )
        }
    }

    // MARK: - Grid matching

    /// If the template is a pure photo grid whose cells exactly tile one of the
    /// Step 01 `GridTemplate` layouts, returns that layout so the grid editor
    /// can open it today. Templates with text/sticker/art/spacer zones or
    /// non-rectangular cells need the template editor and return `nil`.
    public nonisolated static func gridTemplate(matching template: CollageTemplate) -> GridTemplate? {
        guard !template.cells.isEmpty,
              template.cells.allSatisfy({ $0.zoneType == .photo && $0.shape == .rectangle })
        else { return nil }

        let frames = template.cells.map(\.frame)
        return GridTemplate.allCases.first { candidate in
            var remaining = candidate.normalizedCells
            guard remaining.count == frames.count else { return false }
            // Order-insensitive: each template cell must consume exactly one
            // layout cell within tolerance.
            for frame in frames {
                guard let index = remaining.firstIndex(where: { approximatelyEqual($0, frame) })
                else { return false }
                remaining.remove(at: index)
            }
            return true
        }
    }

    private nonisolated static func approximatelyEqual(
        _ a: CGRect, _ b: CGRect, tolerance: CGFloat = 0.001
    ) -> Bool {
        abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }

    /// A deterministic digest (FNV-1a over the thumbnail-relevant fields) that
    /// changes whenever the rendered appearance would. Swift's `Hashable` is
    /// per-process seeded, so it can't key an on-disk cache.
    nonisolated static func contentFingerprint(of template: CollageTemplate) -> String {
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        func mix(_ value: String) {
            for byte in value.utf8 { hash = (hash ^ UInt64(byte)) &* 0x0000_0100_0000_01b3 }
        }
        mix(template.canvasAspectRatio)
        mix(String(describing: template.background))
        for cell in template.cells {
            mix("\(cell.type)|\(cell.shape.rawValue)|\(cell.cornerRadius)|\(cell.stickerID ?? "")|")
            mix("\(cell.frame.minX),\(cell.frame.minY),\(cell.frame.width),\(cell.frame.height);")
            // Text zones now render into the thumbnail, so their content + styling
            // must move the fingerprint or an edited caption would serve a stale image.
            if let t = cell.textStyle {
                mix("txt:\(t.text)|\(t.fontName)|\(t.fontSize)|\(t.colorHex)|\(t.alignmentRaw)")
                mix("|\(t.letterSpacing)|\(t.lineHeight)|\(t.opacity)|\(t.isBold)\(t.isItalic)\(t.isUnderlined);")
            }
        }
        return String(hash, radix: 36)
    }

    // MARK: - Editor layout

    /// The editable geometry for a template: its photo zones become editor cells
    /// (the `.template` case of `CollageLayout`). Text/sticker/art/spacer zones
    /// are editor overlays handled by later 03a slices and are not included.
    public nonisolated static func editorLayout(for template: CollageTemplate) -> TemplateLayout {
        TemplateLayout(
            templateID: template.id,
            name: template.name,
            aspectRatio: template.canvasAspectRatio,
            cells: template.cells
                .filter { $0.zoneType == .photo }
                .map { TemplateLayoutCell(frame: $0.frame, clip: clipShape(for: $0.shape)) }
        )
    }

    // MARK: - Helpers

    /// Maps a template's declared `CellShape` to the renderer's parametric clip.
    /// Polygon shapes need per-template point data (a later editor concern); for
    /// the catalog they clip to their bounding rectangle.
    nonisolated static func clipShape(for shape: CellShape) -> CellClipShape {
        switch shape {
        case .circle, .oval: return .ellipse
        default: return .rectangle
        }
    }

    /// All candidate template JSON URLs. Resources are added as a flat group, so
    /// we scan the `Templates` subdirectory first and fall back to the bundle root.
    private func bundledTemplateURLs() -> [URL] {
        if let inSubdir = bundle.urls(forResourcesWithExtension: "json", subdirectory: "Templates"),
           !inSubdir.isEmpty {
            return inSubdir
        }
        return bundle.urls(forResourcesWithExtension: "json", subdirectory: nil) ?? []
    }

    private var thumbnailDirectory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return nil }
        let dir = caches.appendingPathComponent("TemplateThumbnails", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    private func loadDiskThumbnail(key: String) -> CGImage? {
        guard let url = thumbnailDirectory?.appendingPathComponent("\(key).png"),
              let data = try? Data(contentsOf: url),
              let image = UIImage(data: data)?.cgImage else { return nil }
        return image
    }

    private func storeDiskThumbnail(_ image: CGImage, key: String) {
        guard let url = thumbnailDirectory?.appendingPathComponent("\(key).png"),
              let data = UIImage(cgImage: image).pngData() else { return }
        try? data.write(to: url, options: .atomic)
    }
}
