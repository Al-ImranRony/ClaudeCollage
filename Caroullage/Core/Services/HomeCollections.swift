//
//  HomeCollections.swift
//  Caroullage
//
//  Home retention, phase 2 — what Home shows below the hero, as data.
//
//  Home used to show three fixed strips: the same nine templates, three video
//  showcases and six carousels on every launch, forever. The apps this one is
//  measured against (Unfold, SCRL) sell COLLECTIONS — a name, a reason, a
//  season, a "new" mark — and change them. There is no server here and no
//  plan for one, so the collections are a bundled JSON file and the change
//  comes from the calendar: `HomeCollectionPlanner` picks which of these to
//  show today, in which order, from a date window, the week number and what
//  the user said they make in onboarding.
//
//  Every id in here resolves against the catalogs the app already ships
//  (`TemplateService.templates`, `.carouselTemplates`,
//  `SampleContentCatalog.videoShowcases`); an id that does not resolve is
//  skipped, a collection with nothing left hides, and a missing or corrupt file
//  falls back to the three strips Home had before — so this can never make
//  Home emptier than it was.
//

import Foundation

/// One named strip on Home.
public struct HomeCollection: Decodable, Sendable, Equatable, Identifiable {

    public enum Kind: String, Decodable, Sendable {
        case photo, video, carousel
    }

    /// A span of the year, "MM-dd" to "MM-dd" inclusive. `start` after `end`
    /// wraps the new year ("11-16" to "01-05" is the holiday season).
    public struct Window: Decodable, Sendable, Equatable {
        public let start: String
        public let end: String

        public init(start: String, end: String) {
            self.start = start
            self.end = end
        }
    }

    public let id: String
    /// A key in the String Catalog, not display text: the file is data and
    /// the eleven translations live where every other string's do.
    public let titleKey: String
    public let subtitleKey: String?
    public let kind: Kind
    /// Template ids (`photo`, `carousel`) or video showcase ids (`video`).
    public let itemIDs: [String]
    /// When set, the collection is shown only inside the window, and pinned
    /// to the top while it is.
    public let window: Window?
    /// A collection that just landed: pinned to the top and badged "NEW".
    public let isNew: Bool
    /// Onboarding answers (`CreatorKind` raw values) this collection is for.
    /// A match lifts it above the rotating remainder.
    public let creatorKinds: [String]
    /// When set, only this many items are shown, sliced from `itemIDs` by the
    /// ISO week, so the strip is different every week without anyone editing
    /// the file.
    public let weeklyPick: Int?
    /// The Collage tab category "See All" lands on (`photo` collections).
    public let galleryCategory: String?
    /// The Carousel tab type "See All" lands on (`carousel` collections);
    /// nil means every type.
    public let carouselType: String?
    /// Always shown, after everything the planner chose, never capped: the
    /// three catalog strips Home has carried since Step 07.
    public let isPillar: Bool
    /// Ties between pinned collections break on this, higher first.
    public let priority: Int

    public init(
        id: String, titleKey: String, subtitleKey: String? = nil, kind: Kind,
        itemIDs: [String], window: Window? = nil, isNew: Bool = false,
        creatorKinds: [String] = [], weeklyPick: Int? = nil,
        galleryCategory: String? = nil, carouselType: String? = nil,
        isPillar: Bool = false, priority: Int = 0
    ) {
        self.id = id
        self.titleKey = titleKey
        self.subtitleKey = subtitleKey
        self.kind = kind
        self.itemIDs = itemIDs
        self.window = window
        self.isNew = isNew
        self.creatorKinds = creatorKinds
        self.weeklyPick = weeklyPick
        self.galleryCategory = galleryCategory
        self.carouselType = carouselType
        self.isPillar = isPillar
        self.priority = priority
    }

    private enum CodingKeys: String, CodingKey {
        case id, titleKey, subtitleKey, kind, itemIDs, window, isNew, creatorKinds
        case weeklyPick, galleryCategory, carouselType, isPillar, priority
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        titleKey = try c.decode(String.self, forKey: .titleKey)
        subtitleKey = try c.decodeIfPresent(String.self, forKey: .subtitleKey)
        kind = try c.decode(Kind.self, forKey: .kind)
        itemIDs = try c.decode([String].self, forKey: .itemIDs)
        window = try c.decodeIfPresent(Window.self, forKey: .window)
        isNew = try c.decodeIfPresent(Bool.self, forKey: .isNew) ?? false
        creatorKinds = try c.decodeIfPresent([String].self, forKey: .creatorKinds) ?? []
        weeklyPick = try c.decodeIfPresent(Int.self, forKey: .weeklyPick)
        galleryCategory = try c.decodeIfPresent(String.self, forKey: .galleryCategory)
        carouselType = try c.decodeIfPresent(String.self, forKey: .carouselType)
        isPillar = try c.decodeIfPresent(Bool.self, forKey: .isPillar) ?? false
        priority = try c.decodeIfPresent(Int.self, forKey: .priority) ?? 0
    }

    /// The same collection with a different item list — what the weekly pick
    /// and id resolution produce.
    public func with(itemIDs: [String]) -> HomeCollection {
        HomeCollection(
            id: id, titleKey: titleKey, subtitleKey: subtitleKey, kind: kind,
            itemIDs: itemIDs, window: window, isNew: isNew, creatorKinds: creatorKinds,
            weeklyPick: weeklyPick, galleryCategory: galleryCategory,
            carouselType: carouselType, isPillar: isPillar, priority: priority)
    }

    /// The display title, from the catalog.
    public var title: String {
        String(localized: String.LocalizationValue(titleKey))
    }

    public var subtitle: String? {
        subtitleKey.map { String(localized: String.LocalizationValue($0)) }
    }
}

/// The bundled file, decoded once.
@MainActor
public final class HomeCollectionCatalog {

    public static let shared = HomeCollectionCatalog()

    public static let resourceName = "home_collections"

    /// The collections as authored, in file order. Empty when the file is
    /// missing or will not decode — see `collections(fallingBackTo:)`.
    public private(set) var authored: [HomeCollection] = []

    public init(bundle: Bundle = .main) {
        guard let url = bundle.url(forResource: Self.resourceName, withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let file = try? JSONDecoder().decode(File.self, from: data)
        else { return }
        authored = file.collections
    }

    private struct File: Decodable {
        let version: Int
        let collections: [HomeCollection]
    }

    /// What Home plans from: the file, or — when there is no usable file —
    /// the three strips Home carried before collections existed, built from
    /// the sample-content manifest's own curation.
    public func collections(
        fallingBackTo sampleContent: SampleContentCatalog
    ) -> [HomeCollection] {
        authored.isEmpty ? Self.fallback(from: sampleContent) : authored
    }

    /// Step 07's Home, as data.
    public static func fallback(from sampleContent: SampleContentCatalog) -> [HomeCollection] {
        [
            HomeCollection(
                id: "photo-collages", titleKey: "Photo Collages", kind: .photo,
                itemIDs: sampleContent.featuredTemplateIDs.sorted(),
                galleryCategory: "All", isPillar: true),
            HomeCollection(
                id: "video-collages", titleKey: "Video Collages", kind: .video,
                itemIDs: sampleContent.videoShowcases.map(\.id), isPillar: true),
            HomeCollection(
                id: "carousels", titleKey: "Carousels", kind: .carousel,
                itemIDs: sampleContent.featuredCarouselIDs, isPillar: true),
        ]
    }
}
