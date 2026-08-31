//
//  SampleContentCatalog.swift
//  Caroullage
//
//  Step 07 — resolves the bundled sample-content manifest: which licensed
//  sample photos dress which template in the Home showcase. Missing entries
//  degrade per-item (callers fall back to schematic thumbnails); a missing or
//  corrupt manifest degrades the whole showcase the same way. Never fatal.
//

import Foundation
import UIKit

public struct SampleContentManifest: Decodable, Sendable {
    public struct TemplateEntry: Decodable, Sendable { public let photos: [String] }
    public struct CarouselEntry: Decodable, Sendable { public let framePhotos: [[String]] }
    public struct VideoShowcase: Decodable, Sendable {
        public let id: String
        public let loop: String
        public let poster: String
        public let title: String
        /// A `GridTemplate` raw value — the layout the loop was composed in.
        public let layout: String
    }
    public enum HeroKind: String, Decodable, Sendable, CaseIterable { case template, video, carousel }
    public struct HeroRef: Decodable, Sendable {
        public let kind: HeroKind
        public let id: String
    }

    public let version: Int
    public let templates: [String: TemplateEntry]
    public let carousels: [String: CarouselEntry]
    public let videoShowcases: [VideoShowcase]
    public let hero: [HeroRef]
    /// Which carousels Home's strip leads with, in order.
    ///
    /// Optional so a manifest authored before this key still decodes — the whole
    /// file degrades to nil if any required field is missing, which would take
    /// the entire showcase down over a curation list.
    public let featuredCarousels: [String]?
}

@MainActor
public final class SampleContentCatalog {

    public static let shared = SampleContentCatalog()

    private let bundle: Bundle
    public private(set) var manifest: SampleContentManifest?
    private var imageCache: [String: UIImage] = [:]

    public init(bundle: Bundle = .main) {
        self.bundle = bundle
        if let url = bundle.url(forResource: "sample_content_manifest", withExtension: "json"),
           let data = try? Data(contentsOf: url) {
            manifest = try? JSONDecoder().decode(SampleContentManifest.self, from: data)
        }
    }

    /// The manifest version, folded into preview cache keys so re-authored
    /// sample content invalidates stale renders.
    public var version: Int { manifest?.version ?? 0 }

    public func samplePhotos(forTemplateID id: String) -> [UIImage]? {
        guard let names = manifest?.templates[id]?.photos else { return nil }
        let images = names.compactMap { image(named: $0) }
        // All or nothing: a half-dressed preview looks broken, not aspirational.
        return images.count == names.count ? images : nil
    }

    public func sampleFramePhotos(forCarouselID id: String) -> [[UIImage]]? {
        guard let frames = manifest?.carousels[id]?.framePhotos else { return nil }
        var out: [[UIImage]] = []
        for names in frames {
            let images = names.compactMap { image(named: $0) }
            guard images.count == names.count else { return nil }
            out.append(images)
        }
        return out
    }

    public var videoShowcases: [SampleContentManifest.VideoShowcase] {
        manifest?.videoShowcases ?? []
    }

    public var heroRefs: [SampleContentManifest.HeroRef] { manifest?.hero ?? [] }

    /// The carousels Home features, in the manifest's order.
    ///
    /// Falls back to every dressed carousel when the key is absent, which is
    /// exactly what Home did before the key existed — so an old or partial
    /// manifest still produces a strip rather than none.
    public var featuredCarouselIDs: [String] {
        if let featured = manifest?.featuredCarousels, !featured.isEmpty { return featured }
        guard let carousels = manifest?.carousels else { return [] }
        // Sorted, not raw dictionary order: an unordered fallback would shuffle
        // Home's strip between launches.
        return carousels.keys.sorted()
    }

    public func image(named name: String) -> UIImage? {
        if let cached = imageCache[name] { return cached }
        guard let url = bundle.url(forResource: name, withExtension: "jpg"),
              let image = UIImage(contentsOfFile: url.path) else { return nil }
        imageCache[name] = image
        return image
    }

    public func videoURL(named name: String) -> URL? {
        bundle.url(forResource: name, withExtension: "mp4")
    }

    /// Every still-photo asset name the template and carousel entries mention
    /// (integrity tests). Video posters are deliberately excluded: they ship with
    /// the loops they belong to, so they are validated alongside them rather than
    /// here, where their absence would fail the whole photo set.
    public func allReferencedPhotoNames() -> Set<String> {
        guard let m = manifest else { return [] }
        var names = Set(m.templates.values.flatMap(\.photos))
        m.carousels.values.forEach { $0.framePhotos.forEach { names.formUnion($0) } }
        return names
    }
}
