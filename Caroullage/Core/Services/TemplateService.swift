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
    /// Bounded (Home retention, phase 4): it used to be a dictionary that held
    /// every render for the life of the process, disk-backed but never
    /// evicting. Photo-real showcase previews at up to 900px are large; the
    /// disk copy is what survives, memory only needs what is on screen.
    ///
    /// Bounded by bytes as well as count since 2026-11-20: the Carousel tab's
    /// paged cards hold every slide of every card on screen, which is several
    /// times more images than a count of 120 was sized for, and an image's
    /// cost is its pixels, not its being one image.
    private let thumbnailCache = BoundedImageCache(countLimit: 400, totalCostLimit: 96 * 1024 * 1024)

    /// Renders in progress, by cache key. A card, a prefetch and the hero can
    /// all ask for the same preview in the same moment; they share one render.
    private var inFlight: [String: Task<CGImage?, Never>] = [:]

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

    /// Whether the carousel template itself is marked premium in its JSON.
    public func isPremium(_ template: CarouselTemplate) -> Bool { template.isPremium }

    /// Whether the current user may open the carousel template.
    ///
    /// This overload did not exist until Step 07's gallery, and its absence was
    /// not benign: Home's carousel cards had nothing to ask, so four premium
    /// carousels opened free. Any surface that offers a carousel asks here.
    public func canOpen(_ template: CarouselTemplate) -> Bool {
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
    /// 5 — The obsidian rebrand: `cellWellChip` went from a warm grey to a
    /// neutral one, which every cached thumbnail draws in the old warm tone.
    /// 6 — Carousel previews learned frame styling (outline/shadow), the
    /// blurred-photo backdrop, and seamless panoramic slicing.
    // Internal, not private: `SuggestionPreviewCache` keys its composites on
    // the same revision, so a renderer change invalidates both caches at once.
    static let rendererRevision = 6

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
        if let cached = thumbnailCache.image(for: key) { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache.set(disk, for: key)
            return disk
        }
        guard let image = renderer.render(renderRequest(for: template, maxDimension: maxDimension), scale: 1) else {
            return nil
        }
        thumbnailCache.set(image, for: key)
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
        if let cached = thumbnailCache.image(for: key) { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache.set(disk, for: key)
            return disk
        }

        guard let dressedRequest = dressedShowcaseRequest(
            for: template, sampleContent: sampleContent, maxDimension: maxDimension)
        else { return nil }
        guard let image = renderer.render(dressedRequest, scale: 1) else { return nil }
        thumbnailCache.set(image, for: key)
        storeDiskThumbnail(image, key: key)
        return image
    }

    /// The collage dressed in its manifest photography, as a render request —
    /// shared by the synchronous `showcasePreview` and the async pipeline.
    private func dressedShowcaseRequest(
        for template: CollageTemplate, sampleContent: SampleContentCatalog, maxDimension: CGFloat
    ) -> RenderRequest? {
        guard let photos = sampleContent.samplePhotos(forTemplateID: template.id),
              photos.count == template.cells.filter({ $0.zoneType == .photo }).count
        else { return nil }
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
        return RenderRequest(
            canvasSize: request.canvasSize, background: request.background, cells: dressed,
            textOverlays: request.textOverlays, textFontScale: request.textFontScale,
            stickerOverlays: request.stickerOverlays, stickerImages: request.stickerImages
        )
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
        guard let framePhotos = dressedFramePhotos(for: template, sampleContent: sampleContent)
        else { return nil }

        // No content fingerprint here: `CarouselTemplate` has no equivalent digest,
        // and carousel JSON is bundled — it only changes with the app binary, which
        // also clears the caches directory on install.
        let key = "showcase-carousel-\(template.id)"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(frameMaxDimension))"
        if let cached = thumbnailCache.image(for: key) { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache.set(disk, for: key)
            return disk
        }

        // The manifest authors its frame arrays in frame order, so sort by `index`
        // rather than trusting the JSON's array order.
        let texts = sampleContent.sampleFrameTexts(forCarouselID: template.id)
        let frames = template.frames.sorted { $0.index < $1.index }.prefix(3)
        var rendered: [CGImage] = []
        for (offset, frame) in frames.enumerated() {
            guard offset < framePhotos.count,
                  let image = renderCarouselFrame(frame, photos: framePhotos[offset],
                                                  texts: Self.copy(texts, at: offset),
                                                  of: template, maxDimension: frameMaxDimension)
            else { return nil }
            rendered.append(image)
        }
        guard let strip = Self.compositeStrip(rendered) else { return nil }
        thumbnailCache.set(strip, for: key)
        storeDiskThumbnail(strip, key: key)
        return strip
    }

    /// The carousel's FIRST frame alone, dressed in its manifest sample photos
    /// and rendered at the template's true canvas aspect ratio.
    ///
    /// Deliberately not `showcasePreview`, which composites three frames into a
    /// wide strip. A strip is right for Home, whose carousel cards are wide by
    /// construction. It is wrong for the Carousel gallery, which is a masonry
    /// grid: masonry has nothing to stagger unless a 9:16 template comes back
    /// tall and a 1:1 one comes back square. That property is what
    /// `CarouselCoverPreviewTests` pins.
    ///
    /// Returns `nil` without a manifest entry, so the caller falls back to
    /// `schematicCover`.
    public func showcaseCover(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480
    ) -> CGImage? {
        guard let framePhotos = dressedFramePhotos(for: template, sampleContent: sampleContent),
              let first = framePhotos.first,
              let frame = template.frames.min(by: { $0.index < $1.index })
        else { return nil }

        // The cover IS frame 0 — same photos, same copy, same size — so it shares
        // frame 0's key: the paged card's first page and its cover are one render.
        let key = frameKey(template, offset: 0, sampleContent: sampleContent, maxDimension: maxDimension)
        if let cached = thumbnailCache.image(for: key) { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache.set(disk, for: key)
            return disk
        }

        guard let image = renderCarouselFrame(
            frame, photos: first,
            texts: sampleContent.sampleFrameTexts(forCarouselID: template.id)?.first,
            of: template, maxDimension: maxDimension)
        else { return nil }
        thumbnailCache.set(image, for: key)
        storeDiskThumbnail(image, key: key)
        return image
    }

    /// Every frame of the carousel, dressed and rendered separately, in frame
    /// order — the Home hero's deck deals them out one card per frame.
    ///
    /// All or nothing, like `showcasePreview`: a deck with a missing card reads
    /// as a broken carousel, so any frame that cannot be dressed empties the
    /// result and the caller falls back to the strip.
    public func showcaseFrames(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480,
        limit: Int = 5
    ) -> [CGImage] {
        guard let framePhotos = dressedFramePhotos(for: template, sampleContent: sampleContent)
        else { return [] }
        let texts = sampleContent.sampleFrameTexts(forCarouselID: template.id)
        let frames = template.frames.sorted { $0.index < $1.index }.prefix(limit)
        var rendered: [CGImage] = []
        for (offset, frame) in frames.enumerated() {
            let key = frameKey(template, offset: offset, sampleContent: sampleContent,
                               maxDimension: maxDimension)
            if let cached = thumbnailCache.image(for: key) ?? loadDiskThumbnail(key: key) {
                thumbnailCache.set(cached, for: key)
                rendered.append(cached)
                continue
            }
            guard offset < framePhotos.count,
                  let image = renderCarouselFrame(
                    frame, photos: framePhotos[offset], texts: Self.copy(texts, at: offset),
                    of: template, maxDimension: maxDimension)
            else { return [] }
            thumbnailCache.set(image, for: key)
            storeDiskThumbnail(image, key: key)
            rendered.append(image)
        }
        return rendered
    }

    /// `showcaseFrames`, with every disk read, decode and render off the main
    /// actor (see "Async preview pipeline" below).
    ///
    /// Same frames, same cache keys, same all-or-nothing rule. Frames render in
    /// parallel, and each is shared with any other caller asking for it.
    public func showcaseFramesInBackground(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480,
        limit: Int = 5,
        priority: TaskPriority = .userInitiated
    ) async -> [CGImage] {
        let frames = Array(template.frames.sorted { $0.index < $1.index }.prefix(limit))
        // The same gate the synchronous path has always had: every named
        // sample photo must resolve before any frame — even a cached one — is
        // served as "dressed".
        guard !frames.isEmpty, sampleContent.sampleFramePhotos(forCarouselID: template.id) != nil
        else { return [] }
        // Resolved lazily, once, and only if some frame actually has to render:
        // a disk hit never touches the sample photography.
        let dressing = LazyDressing { [self] in
            dressedFramePhotos(for: template, sampleContent: sampleContent)
                .map { ($0, sampleContent.sampleFrameTexts(forCarouselID: template.id)) }
        }
        // One task per frame, so frames render in parallel; each is shared with
        // any other caller asking for the same frame.
        let tasks = frames.enumerated().map { offset, frame in
            let key = frameKey(template, offset: offset, sampleContent: sampleContent,
                               maxDimension: maxDimension)
            return Task(priority: priority) { @MainActor [self] in
                await loadImage(forKey: key, priority: priority) { [self] in
                    guard let dressed = dressing.value, offset < dressed.photos.count else { return nil }
                    return carouselFrameRequest(
                        frame, photos: dressed.photos[offset], texts: Self.copy(dressed.texts, at: offset),
                        of: template, maxDimension: maxDimension)
                }
            }
        }
        var images: [CGImage?] = []
        for task in tasks { images.append(await task.value) }
        // All or nothing: a deck with a missing card reads as a broken carousel.
        let rendered = images.compactMap { $0 }
        return rendered.count == frames.count ? rendered : []
    }

    /// The same first frame with its photo zones left as empty wells — the
    /// wireframe a gallery card falls back to.
    ///
    /// Unlike `showcaseCover` this asks the manifest for nothing, so it survives
    /// a missing or corrupt manifest. It is the reason a Carousel gallery card
    /// can never render blank, which `showcasePreview`'s deliberate "no
    /// fallback" rule leaves open for Home (Home FEATURES carousels; the gallery
    /// LISTS them, and a list may not have holes).
    public func schematicCover(
        for template: CarouselTemplate,
        maxDimension: CGFloat = 480
    ) -> CGImage? {
        guard let frame = template.frames.min(by: { $0.index < $1.index }) else { return nil }

        // No sample-content version in the key: this render does not read the
        // manifest, so re-dressing a template cannot change it.
        // Frame 0's wireframe key: the same render the async pipeline makes.
        let key = schematicFrameKey(template, offset: 0, maxDimension: maxDimension)
        if let cached = thumbnailCache.image(for: key) { return cached }
        if let disk = loadDiskThumbnail(key: key) {
            thumbnailCache.set(disk, for: key)
            return disk
        }

        guard let image = renderCarouselFrame(
            frame, photos: nil, of: template, maxDimension: maxDimension)
        else { return nil }
        thumbnailCache.set(image, for: key)
        storeDiskThumbnail(image, key: key)
        return image
    }

    /// The photos each frame is dressed in, in frame order.
    ///
    /// A panoramic template is dressed in ONE photograph cut across every frame
    /// — the manifest's first photo, sliced by the same `PanoramicStitcher` the
    /// editor uses on the user's own panorama. Dressing each page in a different
    /// photo (which is what the manifest's per-frame lists alone would do) made
    /// a swipe through a "panorama" card show three unrelated pictures: the one
    /// thing a seamless carousel exists to avoid. Equal slices that are
    /// aspect-filled into equal frames crop identically, so the edges meet.
    private func dressedFramePhotos(
        for template: CarouselTemplate, sampleContent: SampleContentCatalog
    ) -> [[UIImage]]? {
        guard let photos = sampleContent.sampleFramePhotos(forCarouselID: template.id) else { return nil }
        guard template.carouselType == .panoramic,
              let source = photos.first?.first?.cgImage,
              template.frames.allSatisfy({ $0.cells.filter { $0.zoneType == .photo }.count == 1 })
        else { return photos }
        let slices = PanoramicStitcher().split(
            image: source, into: template.frames.count,
            axis: template.panoramicSource?.splitAxis ?? .horizontal)
        guard slices.count == template.frames.count else { return photos }
        return slices.map { [UIImage(cgImage: $0)] }
    }

    /// One carousel frame, rendered through the shared renderer.
    ///
    /// `photos == nil` renders the frame SCHEMATICALLY — every photo zone left
    /// as an empty well, exactly as `renderRequest(for: CollageTemplate)` does
    /// for a standard template's thumbnail. That is the fallback a gallery card
    /// falls back to, and routing it through this method rather than a second
    /// drawing path is what keeps one answer to "where do a frame's cells go".
    private func renderCarouselFrame(
        _ frame: CarouselTemplateFrame, photos: [UIImage]?, texts: [String]? = nil,
        of template: CarouselTemplate, maxDimension: CGFloat
    ) -> CGImage? {
        carouselFrameRequest(frame, photos: photos, texts: texts, of: template, maxDimension: maxDimension)
            .flatMap { renderer.render($0, scale: 1) }
    }

    /// Everything `renderCarouselFrame` decides, short of drawing it: the request
    /// is Sendable, so a caller may hand it to the renderer off the main actor.
    private func carouselFrameRequest(
        _ frame: CarouselTemplateFrame, photos: [UIImage]?, texts: [String]? = nil,
        of template: CarouselTemplate, maxDimension: CGFloat
    ) -> RenderRequest? {
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

        // Only meaningful when photos were supplied. The manifest's per-frame
        // array is guaranteed internally consistent (every name it lists
        // resolves) but is never checked against how many `.photo` zones THIS
        // frame actually has, so a short array would otherwise leave trailing
        // zones as empty wells baked into a supposedly photo-real preview.
        // Schematic renders have no array to be short.
        if let photos { guard photos.count == photoCells.count else { return nil } }

        let cells: [RenderCell] = layout.cells.enumerated().map { index, layoutCell in
            let absolute = CGRect(
                x: layoutCell.frame.origin.x * canvas.width,
                y: layoutCell.frame.origin.y * canvas.height,
                width: layoutCell.frame.size.width * canvas.width,
                height: layoutCell.frame.size.height * canvas.height
            )
            return RenderCell(
                frame: absolute,
                image: photos.flatMap { index < $0.count ? $0[index].cgImage : nil },
                transform: CellTransform(panX: 0, panY: 0, zoom: 1, rotationRadians: 0),
                cornerRadius: CGFloat(photoCells[index].cornerRadius)
                    * min(canvas.width, canvas.height),
                clipShape: layoutCell.clip
            )
        }

        // A `.photoBlur` backdrop is left nil on purpose: `CollageRenderer`
        // derives it from the first photo cell, as the editor does, on the
        // render's background thread rather than here on the main actor.

        // Outline width is authored in reference-canvas points; this canvas is
        // `scale` of that, so the stroke shrinks with it. (Shadow geometry is
        // already relative to the canvas's short side.)
        var style = template.frameStyle
        style.outlineWidth *= Double(scale)

        // The frame's own captions and stickers ride along, so a previewed page
        // looks like the page the editor opens, not a bare photo grid.
        return RenderRequest(
            canvasSize: canvas, background: template.background, cells: cells,
            textOverlays: Self.dressed(frame.cells.compactMap(\.textStyle), with: texts),
            textFontScale: scale,
            stickerOverlays: Self.stickerOverlays(for: frame.cells),
            frameStyle: style
        )
    }

    private static func copy(_ texts: [[String]]?, at frame: Int) -> [String]? {
        guard let texts, texts.indices.contains(frame) else { return nil }
        return texts[frame]
    }

    /// The frame's text overlays with the showcase's copy swapped in, in order.
    /// Zones beyond the copy provided keep the template's own text.
    private static func dressed(_ overlays: [TextOverlay], with texts: [String]?) -> [TextOverlay] {
        guard let texts else { return overlays }
        return overlays.enumerated().map { index, overlay in
            guard index < texts.count else { return overlay }
            var dressed = overlay
            dressed.text = texts[index]
            return dressed
        }
    }

    /// Lays rendered frames out left to right with a small gap, every frame after
    /// the first slightly shorter and vertically centred. The stagger is what makes
    /// the strip read as swipeable pages rather than one very wide photograph.
    nonisolated private static func compositeStrip(_ frames: [CGImage]) -> CGImage? {
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

    // MARK: - Async preview pipeline (2026-11-20)
    //
    // Every card on Home and on the two browse tabs asks for its picture here.
    // The rules, and why:
    //
    //  • A memory hit is answered synchronously (`cached…`), so a card scrolled
    //    back into view shows its picture in the same frame — no placeholder,
    //    no fade, nothing for the eye to catch.
    //  • Everything else is async and OFF the main thread: the PNG read and its
    //    decode (a lazily-decoded image would otherwise decode at the next
    //    Core Animation commit, on main, mid-scroll), the render, and the PNG
    //    encode for the disk cache. Only building the render request stays on
    //    the main actor — it reads the catalog and manifest, and it is cheap.
    //  • Concurrent requests for one key share one render (`inFlight`), so a
    //    prefetch that is still running when its card arrives is not repeated.
    //  • Nothing here touches the network. Every preview is drawn from bundled
    //    sample photography, so the catalog looks the same offline.

    /// The memory cache's answer and nothing more — never reads disk, never
    /// renders. Safe to call from `cellForItemAt`.
    func cachedImage(forKey key: String) -> CGImage? {
        thumbnailCache.image(for: key)
    }

    /// The pipeline: memory, then a shared in-flight render, then disk, then a
    /// fresh render. `makeRequest` runs on the main actor and only on a disk
    /// miss; returning nil means "this cannot be drawn" and yields nil.
    func loadImage(
        forKey key: String,
        priority: TaskPriority = .userInitiated,
        makeRequest: @escaping @MainActor () -> RenderRequest?
    ) async -> CGImage? {
        if let hit = thumbnailCache.image(for: key) { return hit }
        if let running = inFlight[key] { return await running.value }

        let url = diskURL(forKey: key)
        let renderer = self.renderer
        let task = Task<CGImage?, Never>(priority: priority) { @MainActor in
            if let url, let disk = await Task.detached(priority: priority, operation: {
                Self.decodedImage(at: url)
            }).value {
                return disk
            }
            guard let request = makeRequest() else { return nil }
            return await Task.detached(priority: priority) { () -> CGImage? in
                guard let image = renderer.render(request, scale: 1) else { return nil }
                if let url { Self.writePNG(image, to: url) }
                return image
            }.value
        }
        inFlight[key] = task
        let image = await task.value
        inFlight[key] = nil
        if let image { thumbnailCache.set(image, for: key) }
        return image
    }

    // MARK: Collage templates

    /// The photo-real preview if it is in memory, else the schematic if that
    /// is. Synchronous; never renders.
    public func cachedShowcasePreview(
        for template: CollageTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 640
    ) -> CGImage? {
        // The wireframe only for a template the manifest does not dress. A
        // wireframe that happens to be in memory must never stand in for a
        // dressed preview that is merely not loaded yet: the card would take
        // it as final and never load the real one.
        isDressed(template, sampleContent: sampleContent)
            ? cachedImage(forKey: showcaseKey(template, sampleContent: sampleContent, maxDimension: maxDimension))
            : cachedImage(forKey: thumbnailKey(template, maxDimension: 300))
    }

    /// Whether the manifest dresses this collage at all.
    private func isDressed(_ template: CollageTemplate, sampleContent: SampleContentCatalog) -> Bool {
        sampleContent.manifest?.templates[template.id] != nil
    }

    /// Whether the manifest dresses this carousel at all.
    private func isDressed(_ template: CarouselTemplate, sampleContent: SampleContentCatalog) -> Bool {
        sampleContent.manifest?.carousels[template.id] != nil
    }

    /// `showcasePreview` falling back to `thumbnail`, through the pipeline.
    public func loadShowcasePreview(
        for template: CollageTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 640,
        priority: TaskPriority = .userInitiated
    ) async -> CGImage? {
        // The same "fully dressed or not at all" check `showcasePreview` makes
        // before its cache lookup, so a stale render is never served.
        let photoZones = template.cells.filter { $0.zoneType == .photo }.count
        if sampleContent.samplePhotos(forTemplateID: template.id)?.count == photoZones,
           let dressed = await loadImage(
            forKey: showcaseKey(template, sampleContent: sampleContent, maxDimension: maxDimension),
            priority: priority,
            makeRequest: { [self] in
                dressedShowcaseRequest(for: template, sampleContent: sampleContent,
                                       maxDimension: maxDimension)
            }) {
            return dressed
        }
        return await loadImage(forKey: thumbnailKey(template, maxDimension: 300), priority: priority) { [self] in
            renderRequest(for: template, maxDimension: 300)
        }
    }

    // MARK: Carousel templates

    /// Frame 0 if it is in memory (photo-real, else wireframe). Synchronous.
    public func cachedShowcaseCover(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480
    ) -> CGImage? {
        // Same rule as `cachedShowcasePreview`: the wireframe only when the
        // manifest does not dress the template.
        isDressed(template, sampleContent: sampleContent)
            ? cachedImage(forKey: frameKey(template, offset: 0, sampleContent: sampleContent,
                                           maxDimension: maxDimension))
            : cachedImage(forKey: schematicFrameKey(template, offset: 0, maxDimension: maxDimension))
    }

    /// The photo-real cover, falling back to the wireframe — a gallery card is
    /// never blank.
    public func loadShowcaseCover(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480,
        priority: TaskPriority = .userInitiated
    ) async -> CGImage? {
        if let first = await showcaseFramesInBackground(
            for: template, sampleContent: sampleContent, maxDimension: maxDimension, limit: 1,
            priority: priority).first {
            return first
        }
        return await loadSchematicFrames(for: template, maxDimension: maxDimension, limit: 1,
                                         priority: priority).first
    }

    /// Every frame, if every one is in memory; nil otherwise. Lets a paged
    /// card that scrolls back into view fill all its pages in one frame.
    public func cachedShowcaseFrames(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480,
        limit: Int = CarouselService.maxFrames,
        allowsSchematic: Bool = true
    ) -> [CGImage]? {
        let count = min(template.frames.count, limit)
        guard count > 0 else { return nil }
        // All dressed or all wireframe, never a mix — the rule
        // `loadShowcaseFrames` keeps — and the wireframe only for a template
        // the manifest does not dress.
        let dressed = isDressed(template, sampleContent: sampleContent)
        guard dressed || allowsSchematic else { return nil }
        var out: [CGImage] = []
        for offset in 0..<count {
            let key = dressed
                ? frameKey(template, offset: offset, sampleContent: sampleContent, maxDimension: maxDimension)
                : schematicFrameKey(template, offset: offset, maxDimension: maxDimension)
            guard let image = cachedImage(forKey: key) else { return nil }
            out.append(image)
        }
        return out
    }

    /// Every frame dressed, or every frame as a wireframe — never a mix.
    public func loadShowcaseFrames(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        maxDimension: CGFloat = 480,
        limit: Int = CarouselService.maxFrames,
        priority: TaskPriority = .userInitiated
    ) async -> [CGImage] {
        let dressed = await showcaseFramesInBackground(
            for: template, sampleContent: sampleContent, maxDimension: maxDimension, limit: limit,
            priority: priority)
        if !dressed.isEmpty { return dressed }
        return await loadSchematicFrames(for: template, maxDimension: maxDimension, limit: limit,
                                         priority: priority)
    }

    /// The wireframes, through the pipeline.
    public func loadSchematicFrames(
        for template: CarouselTemplate,
        maxDimension: CGFloat = 480,
        limit: Int = CarouselService.maxFrames,
        priority: TaskPriority = .userInitiated
    ) async -> [CGImage] {
        let frames = Array(template.frames.sorted { $0.index < $1.index }.prefix(limit))
        var out: [CGImage] = []
        for (offset, frame) in frames.enumerated() {
            let key = schematicFrameKey(template, offset: offset, maxDimension: maxDimension)
            if let image = await loadImage(forKey: key, priority: priority, makeRequest: { [self] in
                carouselFrameRequest(frame, photos: nil, of: template, maxDimension: maxDimension)
            }) {
                out.append(image)
            }
        }
        return out
    }

    /// The three-frame strip (`showcasePreview(for: CarouselTemplate)`), with
    /// its frames and the composite drawn off the main actor.
    public func loadShowcaseStrip(
        for template: CarouselTemplate,
        sampleContent: SampleContentCatalog = .shared,
        frameMaxDimension: CGFloat = 480
    ) async -> CGImage? {
        let key = stripKey(template, sampleContent: sampleContent, frameMaxDimension: frameMaxDimension)
        if let hit = cachedImage(forKey: key) { return hit }
        let frames = await showcaseFramesInBackground(
            for: template, sampleContent: sampleContent, maxDimension: frameMaxDimension, limit: 3)
        guard !frames.isEmpty else { return nil }
        guard let strip = await Task.detached(priority: .userInitiated, operation: {
            Self.compositeStrip(frames)
        }).value else { return nil }
        thumbnailCache.set(strip, for: key)
        return strip
    }

    // MARK: Prefetch

    /// Warms the cache for cards about to scroll in. Low priority, and shared
    /// with the card's own request if it arrives while this is still running.
    public func prefetchCovers(for templates: [CarouselTemplate]) {
        for template in templates where cachedShowcaseCover(for: template) == nil {
            Task(priority: .utility) { _ = await loadShowcaseCover(for: template, priority: .utility) }
        }
    }

    /// The first `limit` dressed frames — what Home's deck cards deal out.
    public func prefetchFrames(for templates: [CarouselTemplate], limit: Int) {
        for template in templates
        where cachedShowcaseFrames(for: template, limit: limit, allowsSchematic: false) == nil {
            Task(priority: .utility) {
                _ = await showcaseFramesInBackground(for: template, limit: limit, priority: .utility)
            }
        }
    }

    public func prefetchPreviews(for templates: [CollageTemplate], maxDimension: CGFloat = 640) {
        for template in templates
        where cachedShowcasePreview(for: template, maxDimension: maxDimension) == nil {
            Task(priority: .utility) {
                _ = await loadShowcasePreview(for: template, maxDimension: maxDimension, priority: .utility)
            }
        }
    }

    // MARK: Keys

    private func thumbnailKey(_ template: CollageTemplate, maxDimension: CGFloat) -> String {
        "\(template.id)-\(Self.contentFingerprint(of: template))"
            + "-r\(Self.rendererRevision)@\(Int(maxDimension))"
    }

    private func showcaseKey(
        _ template: CollageTemplate, sampleContent: SampleContentCatalog, maxDimension: CGFloat
    ) -> String {
        "showcase-\(template.id)-\(Self.contentFingerprint(of: template))"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(maxDimension))"
    }

    private func frameKey(
        _ template: CarouselTemplate, offset: Int, sampleContent: SampleContentCatalog, maxDimension: CGFloat
    ) -> String {
        "frame-carousel-\(template.id)-\(offset)"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(maxDimension))"
    }

    private func schematicFrameKey(_ template: CarouselTemplate, offset: Int, maxDimension: CGFloat) -> String {
        "schematic-carousel-\(template.id)-\(offset)"
            + "-r\(Self.rendererRevision)@\(Int(maxDimension))"
    }

    private func stripKey(
        _ template: CarouselTemplate, sampleContent: SampleContentCatalog, frameMaxDimension: CGFloat
    ) -> String {
        "showcase-carousel-\(template.id)"
            + "-s\(sampleContent.version)-r\(Self.rendererRevision)@\(Int(frameMaxDimension))"
    }

    // MARK: Disk (nonisolated: called from background tasks)

    private lazy var diskDirectory: URL? = thumbnailDirectory

    private func diskURL(forKey key: String) -> URL? {
        diskDirectory?.appendingPathComponent("\(key).png")
    }

    /// Reads and fully DECODES a cached PNG. `preparingForDisplay()` is the
    /// point: without it the decode is deferred to the first Core Animation
    /// commit that draws the image — on the main thread, during the scroll.
    nonisolated private static func decodedImage(at url: URL) -> CGImage? {
        guard let data = try? Data(contentsOf: url), let image = UIImage(data: data) else { return nil }
        return (image.preparingForDisplay() ?? image).cgImage
    }

    nonisolated private static func writePNG(_ image: CGImage, to url: URL) {
        guard let data = UIImage(cgImage: image).pngData() else { return }
        try? data.write(to: url, options: .atomic)
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

    /// Deletes every rendered preview on disk. Debug-only callers (the
    /// scroll-performance suite's cold-cache launch); the cache rebuilds itself.
    static func purgePreviewDiskCache() {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
        else { return }
        try? FileManager.default.removeItem(
            at: caches.appendingPathComponent("TemplateThumbnails", isDirectory: true))
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

/// A carousel's sample dressing, worked out on first use and then remembered —
/// shared by the frames of one `showcaseFramesInBackground` call.
@MainActor
private final class LazyDressing {
    typealias Dressing = (photos: [[UIImage]], texts: [[String]]?)
    private let make: () -> Dressing?
    private var resolved: Dressing??

    init(_ make: @escaping () -> Dressing?) { self.make = make }

    var value: Dressing? {
        if let resolved { return resolved }
        let made = make()
        resolved = .some(made)
        return made
    }
}

/// `NSCache` for `CGImage`, with the value semantics the service's own cache
/// had: a string key in, an image or nil out.
final class BoundedImageCache {
    private let cache = NSCache<NSString, CGImage>()

    init(countLimit: Int, totalCostLimit: Int = 0) {
        cache.countLimit = countLimit
        cache.totalCostLimit = totalCostLimit
    }

    func image(for key: String) -> CGImage? {
        cache.object(forKey: key as NSString)
    }

    /// Costed by decoded size, so the byte limit evicts big renders first.
    func set(_ image: CGImage, for key: String) {
        cache.setObject(image, forKey: key as NSString, cost: image.bytesPerRow * image.height)
    }
}
