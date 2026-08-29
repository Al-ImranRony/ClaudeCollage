//
//  TemplateService.swift
//  Caroullage
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

    /// Bumped whenever `CollageRenderer` changes how it draws chrome, so cached
    /// thumbnails rendered by an older look are never served.
    ///
    /// 2 — Step 05b: the empty-cell well moved from the system greys to the
    /// deterministic `Theme.Color.cellWell` tokens.
    /// 3 — Step 06: empty zones gained an outline and a circular "+" chip
    /// (`EmptyCellChrome`), so every cached thumbnail draws the old bare glyph.
    /// 4 — Step 06: the well went from warm grey to the near-white the video
    /// editor's slots use, and the outline down to a hairline.
    private static let rendererRevision = 4

    /// A `maxDimension`-bounded thumbnail for the template, rendered once via the
    /// shared `CollageRenderer` and cached in memory + on disk. Photo zones show
    /// the empty-cell placeholder (there is no user imagery yet).
    public func thumbnail(for template: CollageTemplate, maxDimension: CGFloat = 300) -> CGImage? {
        // The key carries a content fingerprint so a re-authored template (same
        // id, new geometry/background) never serves its stale cached thumbnail,
        // and a renderer revision so a change to how the renderer draws does not
        // either. The fingerprint alone cannot catch the second case: the
        // template did not change, the renderer did — which is exactly what
        // happened when the empty-cell well moved off the system greys.
        let key = "\(template.id)-\(Self.contentFingerprint(of: template))"
            + "-r\(Self.rendererRevision)@\(Int(maxDimension))"
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

    // MARK: - Showcase previews (Step 07)

    /// A photo-real preview of the template, dressed in its bundled sample
    /// photography. Rendered through the SAME `CollageRenderer` the editor and
    /// the exporter use, into the template's real zones — so what Home shows is
    /// literally what opening the template produces once your photos land in it.
    /// A separate drawing path here would make that promise aspirational; this
    /// makes it structural.
    ///
    /// Returns `nil` when the template has no manifest entry, so the caller falls
    /// back to the schematic `thumbnail(for:)` rather than presenting a grid of
    /// empty wells as if it were a showcase.
    public func showcasePreview(
        for template: CollageTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 640
    ) -> CGImage? {
        guard let photos = sampleContent.samplePhotos(forTemplateID: template.id) else { return nil }

        // `SampleContentCatalog` only guarantees that every name IT lists resolves
        // to a bundled image — it has no idea how many `.photo` zones the template
        // actually has. A template that gains a zone (or a manifest entry authored
        // short) would otherwise sail past this point and render with the extra
        // zones left as bare empty wells: half-dressed, which is exactly what this
        // method's contract says a showcase must never be. Checked before the cache
        // lookup, not after — an on-disk thumbnail cached while the two were still
        // out of sync must not be served back as if it were valid just because its
        // key still matches.
        let photoZoneCount = template.cells.filter { $0.zoneType == .photo }.count
        guard photos.count == photoZoneCount else { return nil }

        // Same key shape as `thumbnail(for:)` — content fingerprint + renderer
        // revision — plus the sample-content version, because re-dressing a
        // template in the manifest changes the render without touching either.
        let key = "showcase-\(template.id)-\(Self.contentFingerprint(of: template))"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(maxDimension))"
        if let cached = thumbnailCache[key] { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache[key] = disk
            return disk
        }

        let request = renderRequest(for: template, maxDimension: maxDimension)

        // `renderRequest` emits a cell for both `.photo` AND `.art` zones, but the
        // manifest's photo array is sized to `.photo` zones only. Walking the two
        // lists in lockstep works today (no showcased template has an art zone)
        // and would silently hand photo #2 to the art zone the moment one gained
        // it — every photo after it shifting one cell to the left. So re-derive
        // the same filtered source list and consume a sample photo only where the
        // source zone really is a photo zone.
        let sourceCells = template.cells.filter { $0.zoneType == .photo || $0.zoneType == .art }
        guard sourceCells.count == request.cells.count else { return nil }

        var remaining = photos[...]
        var dressed: [RenderCell] = []
        for (source, cell) in zip(sourceCells, request.cells) {
            guard source.zoneType == .photo,
                  let photo = remaining.popFirst(), let image = photo.cgImage else {
                dressed.append(cell)
                continue
            }
            dressed.append(RenderCell(frame: cell.frame, image: image, transform: cell.transform,
                                      cornerRadius: cell.cornerRadius, clipShape: cell.clipShape))
        }

        // Everything else about the request survives untouched: background, the
        // template's typography, its font scale and its seeded stickers.
        let dressedRequest = RenderRequest(
            canvasSize: request.canvasSize, background: request.background, cells: dressed,
            textOverlays: request.textOverlays, textFontScale: request.textFontScale,
            stickerOverlays: request.stickerOverlays, stickerImages: request.stickerImages
        )
        guard let image = renderer.render(dressedRequest, scale: 1) else { return nil }
        thumbnailCache[key] = image
        storeDiskThumbnail(image, key: key)
        return image
    }

    /// A photo-real preview of a carousel: its first three frames rendered through
    /// `CollageRenderer` and composited into one side-by-side strip, so Home can
    /// show at a glance that this template is a multi-page post rather than a
    /// single image.
    ///
    /// Returns `nil` without a manifest entry, and `nil` rather than a partial
    /// strip if any frame fails — a strip missing its last page reads as broken.
    public func showcasePreview(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        frameMaxDimension: CGFloat = 480
    ) -> CGImage? {
        guard let framePhotos = sampleContent.sampleFramePhotos(forCarouselID: template.id)
        else { return nil }

        // No content fingerprint here: `CarouselTemplate` has no equivalent digest,
        // and carousel JSON is bundled — it only changes with the app binary, which
        // also clears the caches directory on install.
        let key = "showcase-carousel-\(template.id)"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(frameMaxDimension))"
        if let cached = thumbnailCache[key] { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache[key] = disk
            return disk
        }

        // The manifest authors its frame arrays in frame order, so sort by `index`
        // rather than trusting the JSON's array order.
        let frames = template.frames.sorted { $0.index < $1.index }.prefix(3)
        var rendered: [CGImage] = []
        for (offset, frame) in frames.enumerated() {
            guard offset < framePhotos.count,
                  let image = renderCarouselFrame(frame, photos: framePhotos[offset],
                                                  of: template, maxDimension: frameMaxDimension)
            else { return nil }
            rendered.append(image)
        }
        guard let strip = Self.compositeStrip(rendered) else { return nil }
        thumbnailCache[key] = strip
        storeDiskThumbnail(strip, key: key)
        return strip
    }

    /// One carousel frame, dressed and rendered through the shared renderer.
    private func renderCarouselFrame(
        _ frame: CarouselTemplateFrame, photos: [UIImage],
        of template: CarouselTemplate, maxDimension: CGFloat
    ) -> CGImage? {
        let native = CanvasSize.size(forAspectRatio: template.canvasAspectRatio)
        let longest = max(native.width, native.height, 1)
        let scale = maxDimension / longest
        let canvas = CGSize(width: (native.width * scale).rounded(),
                            height: (native.height * scale).rounded())

        // Geometry comes from the editor's own layout mapper, so a previewed frame
        // has exactly the cells the carousel editor will open — no second copy of
        // the frame → cells math to drift out of sync.
        let layout = Self.editorLayout(templateID: template.id, name: template.name,
                                       aspectRatio: template.canvasAspectRatio, cells: frame.cells)
        // `TemplateLayoutCell` carries frame + clip but not the authored corner
        // radius, so re-derive that from the same `.photo` filter `editorLayout`
        // applies; the two lists are index-aligned by construction.
        let photoCells = frame.cells.filter { $0.zoneType == .photo }
        guard photoCells.count == layout.cells.count else { return nil }

        // Same defect as the standard-template overload, one level down: the
        // manifest's per-frame photo array is only guaranteed internally
        // consistent (every name it lists resolves), never checked against how
        // many `.photo` zones THIS frame actually has. Without this, a short
        // array would leave the trailing zones with `image: nil` below — empty
        // wells baked into what is supposed to be a photo-real preview — instead
        // of the whole frame (and so the whole carousel strip) degrading to nil.
        guard photos.count == photoCells.count else { return nil }

        let cells: [RenderCell] = layout.cells.enumerated().map { index, layoutCell in
            let absolute = CGRect(
                x: layoutCell.frame.origin.x * canvas.width,
                y: layoutCell.frame.origin.y * canvas.height,
                width: layoutCell.frame.size.width * canvas.width,
                height: layoutCell.frame.size.height * canvas.height
            )
            return RenderCell(
                frame: absolute,
                image: index < photos.count ? photos[index].cgImage : nil,
                transform: CellTransform(panX: 0, panY: 0, zoom: 1, rotationRadians: 0),
                cornerRadius: CGFloat(photoCells[index].cornerRadius)
                    * min(canvas.width, canvas.height),
                clipShape: layoutCell.clip
            )
        }

        // The frame's own captions and stickers ride along, so a previewed page
        // looks like the page the editor opens, not a bare photo grid.
        let request = RenderRequest(
            canvasSize: canvas, background: template.background, cells: cells,
            textOverlays: frame.cells.compactMap(\.textStyle), textFontScale: scale,
            stickerOverlays: Self.stickerOverlays(for: frame.cells)
        )
        return renderer.render(request, scale: 1)
    }

    /// Lays rendered frames out left to right with a small gap, every frame after
    /// the first slightly shorter and vertically centred. The stagger is what makes
    /// the strip read as swipeable pages rather than one very wide photograph.
    private static func compositeStrip(_ frames: [CGImage]) -> CGImage? {
        guard let first = frames.first else { return nil }
        let frameWidth = CGFloat(first.width)
        let frameHeight = CGFloat(first.height)
        guard frameWidth > 0, frameHeight > 0 else { return nil }

        let gap = (frameWidth * 0.02).rounded()
        let inset = (frameHeight * 0.04).rounded()
        let total = CGSize(
            width: frameWidth * CGFloat(frames.count) + gap * CGFloat(frames.count - 1),
            height: frameHeight
        )

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        // Not opaque: the gaps stay transparent so the strip sits on whatever
        // surface Home puts behind it.
        format.opaque = false
        let output = UIGraphicsImageRenderer(size: total, format: format).image { _ in
            for (index, frame) in frames.enumerated() {
                let x = (frameWidth + gap) * CGFloat(index)
                let rect = index == 0
                    ? CGRect(x: x, y: 0, width: frameWidth, height: frameHeight)
                    : CGRect(x: x, y: inset, width: frameWidth, height: frameHeight - inset * 2)
                UIImage(cgImage: frame).draw(in: rect)
            }
        }
        return output.cgImage
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
        stickerOverlays(for: template.cells)
    }

    /// Cells-based core of `stickerOverlays(for:)` — reused by the carousel builder,
    /// which maps each carousel frame's `[TemplateCell]` (same cell type) onto a
    /// GridEditorState.
    public static func stickerOverlays(for cells: [TemplateCell]) -> [StickerOverlay] {
        cells.compactMap { cell in
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
        editorLayout(templateID: template.id, name: template.name,
                     aspectRatio: template.canvasAspectRatio, cells: template.cells)
    }

    /// Cells-based core of `editorLayout(for:)` — reused by the carousel builder so a
    /// carousel frame's photo zones map to editor cells with no duplicated geometry.
    public nonisolated static func editorLayout(
        templateID: String, name: String, aspectRatio: String, cells: [TemplateCell]
    ) -> TemplateLayout {
        TemplateLayout(
            templateID: templateID,
            name: name,
            aspectRatio: aspectRatio,
            cells: cells
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
