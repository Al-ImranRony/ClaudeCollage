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
    private let renderer = CollageRenderer()
    private let entitlements: EntitlementStore

    /// All successfully-parsed bundled templates, populated by `loadBundledTemplates()`.
    public private(set) var templates: [CollageTemplate] = []

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
            guard url.lastPathComponent != "template_schema.json",
                  let data = try? Data(contentsOf: url),
                  let template = try? parser.parse(data: data) else { return nil }
            return template
        }
        templates = parsed.sorted {
            $0.isPremium == $1.isPremium ? $0.name < $1.name : (!$0.isPremium && $1.isPremium)
        }
        return templates
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
        let key = "\(template.id)@\(Int(maxDimension))"
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
    /// Only visual zones (photo / art) become render cells — text, sticker and
    /// spacer zones are interactive overlays handled by the editor.
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

        return RenderRequest(canvasSize: canvas, background: template.background, cells: cells)
    }

    // MARK: - Helpers

    /// Maps a template's declared `CellShape` to the renderer's parametric clip.
    /// Polygon shapes need per-template point data (a later editor concern); for
    /// the catalog they clip to their bounding rectangle.
    static func clipShape(for shape: CellShape) -> CellClipShape {
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
