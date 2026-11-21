//
//  CollageGalleryPlanner.swift
//  Caroullage
//
//  2026-11-21 — what the Collage tab shows, decided as a pure function so it
//  can be tested without a simulator. The view controller only draws the answer.
//
//  The tab has two modes, and the query picks between them:
//
//  - BROWSING (no chip, no filter, no search) is a curated magazine: a paged
//    spotlight of fresh free templates, then themed shelves (Trending, Instant
//    & Booth, Film, Editorial, Photo Dump, the season…), then every template
//    in one grid. Shelves are how the best collage apps sell a catalog — a
//    named style is something to want, where a flat grid of 59 is homework.
//  - FINDING (a chip, a filter or a search) is one flat grid of matches. Once
//    someone has said what they want, more shelves would only be in the way.
//
//  Curation lives in `collage_gallery.json`, beside Home's collections, so a
//  new shelf or a new spotlight pick is an edit to data rather than to code.
//

import Foundation

// MARK: - Curation

public struct CollageGalleryCuration: Decodable, Sendable, Equatable {

    public struct Shelf: Decodable, Sendable, Equatable {
        public let id: String
        /// Localization keys (the English text), resolved at display time.
        public let titleKey: String
        public let subtitleKey: String?
        /// The category the shelf's "See All" lands on, and its source when it
        /// lists no ids of its own.
        public let category: String?
        /// An explicit, ordered pick. Takes precedence over `category`.
        public let templateIDs: [String]?
        /// Calendar months (1–12) the shelf is shown in; nil is always. The
        /// season's shelf leads the gallery while the season lasts and steps
        /// aside the rest of the year rather than going stale.
        public let months: [Int]?
        /// 9:16 shelves get taller cards so a story is not shown as a sliver.
        public let tall: Bool?

        public init(id: String, titleKey: String, subtitleKey: String? = nil, category: String? = nil,
                    templateIDs: [String]? = nil, months: [Int]? = nil, tall: Bool? = nil) {
            self.id = id
            self.titleKey = titleKey
            self.subtitleKey = subtitleKey
            self.category = category
            self.templateIDs = templateIDs
            self.months = months
            self.tall = tall
        }

        public var title: String { String(localized: String.LocalizationValue(titleKey)) }
        public var subtitle: String? { subtitleKey.map { String(localized: String.LocalizationValue($0)) } }
    }

    /// The paged cards at the top, in order. Free templates only — the first
    /// thing the tab offers must be something anyone can open.
    public let spotlight: [String]
    /// Templates that wear a "New" tag, and lead the catalog grid.
    public let newTemplateIDs: [String]
    public let shelves: [Shelf]

    public init(spotlight: [String], newTemplateIDs: [String], shelves: [Shelf]) {
        self.spotlight = spotlight
        self.newTemplateIDs = newTemplateIDs
        self.shelves = shelves
    }

    public static let empty = CollageGalleryCuration(spotlight: [], newTemplateIDs: [], shelves: [])

    /// The bundled curation; `.empty` (a plain catalog grid) if it is missing
    /// or malformed — a curation typo must never cost the user the whole tab.
    public static func bundled(in bundle: Bundle = .main) -> CollageGalleryCuration {
        guard let url = bundle.url(forResource: "collage_gallery", withExtension: "json",
                                   subdirectory: "Collections")
                ?? bundle.url(forResource: "collage_gallery", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let curation = try? JSONDecoder().decode(CollageGalleryCuration.self, from: data)
        else { return .empty }
        return curation
    }
}

// MARK: - Query

/// "How many photos do you have?" — the question a collage maker is really
/// asking when they open the gallery.
public enum CollagePhotoFilter: Int, CaseIterable, Sendable {
    case any = 0, one, two, three, four, five, sixPlus

    public func matches(_ count: Int) -> Bool {
        switch self {
        case .any: return true
        case .sixPlus: return count >= 6
        default: return count == rawValue
        }
    }

    public var title: String {
        switch self {
        case .any: return String(localized: "Any Number")
        case .one: return String(localized: "1 Photo")
        case .sixPlus: return String(localized: "6+ Photos")
        default: return String(localized: "\(rawValue) Photos")
        }
    }
}

public struct CollageGalleryQuery: Equatable, Sendable {
    /// A template category ("instant", "seasonal"…), nil for All.
    public var category: String?
    public var photos: CollagePhotoFilter
    public var ratio: CanvasPreset?
    public var search: String

    public init(category: String? = nil, photos: CollagePhotoFilter = .any,
                ratio: CanvasPreset? = nil, search: String = "") {
        self.category = category
        self.photos = photos
        self.ratio = ratio
        self.search = search
    }

    var trimmedSearch: String { search.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// True when nothing narrows the catalog, which is when the tab browses.
    public var isBrowsing: Bool {
        category == nil && photos == .any && ratio == nil && trimmedSearch.isEmpty
    }
}

// MARK: - Sections

public enum CollageGallerySection: Equatable, Sendable {
    case spotlight([CollageTemplate])
    case shelf(CollageGalleryCuration.Shelf, [CollageTemplate])
    /// Every template, closing the browse mode.
    case catalog([CollageTemplate])
    /// The matches for a narrowing query.
    case results([CollageTemplate])

    /// Stable and unique — the diffable data source's section identifier.
    public var id: String {
        switch self {
        case .spotlight: return "spotlight"
        case let .shelf(shelf, _): return "shelf-\(shelf.id)"
        case .catalog: return "catalog"
        case .results: return "results"
        }
    }

    public var templates: [CollageTemplate] {
        switch self {
        case let .spotlight(t), let .shelf(_, t), let .catalog(t), let .results(t): return t
        }
    }
}

public enum CollageGalleryPlanner {

    /// More than this and a shelf stops being a pick; "See All" is for the rest.
    public static let shelfLimit = 12

    public static func sections(
        templates: [CollageTemplate],
        curation: CollageGalleryCuration,
        query: CollageGalleryQuery,
        month: Int
    ) -> [CollageGallerySection] {
        let ordered = catalogOrder(templates, curation: curation)
        guard query.isBrowsing else {
            let matches = ordered.filter { matches($0, query) }
            return matches.isEmpty ? [] : [.results(matches)]
        }

        let byID = Dictionary(templates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var sections: [CollageGallerySection] = []

        // De-duplicated: an id listed twice in one row would put two identical
        // items in one diffable section, which crashes the tab. A curation typo
        // must never cost the user the whole tab.
        func resolved(_ ids: [String]) -> [CollageTemplate] {
            var seen = Set<String>()
            return ids.compactMap { seen.insert($0).inserted ? byID[$0] : nil }
        }

        let spotlight = resolved(curation.spotlight)
        if !spotlight.isEmpty { sections.append(.spotlight(spotlight)) }
        // Everything an earlier row already showed. A shelf leads with what
        // the user has NOT just scrolled past: "Trending" and "Instant &
        // Booth" opening on the same card one row apart reads as filler.
        var shown = Set(spotlight.map(\.id))

        for shelf in curation.shelves {
            if let months = shelf.months, !months.contains(month) { continue }
            let picks: [CollageTemplate]
            if let ids = shelf.templateIDs {
                picks = resolved(ids)
            } else if let category = shelf.category {
                picks = ordered.filter { $0.category.caseInsensitiveCompare(category) == .orderedSame }
            } else {
                picks = []
            }
            // A shelf of one is a card, not a shelf.
            guard picks.count >= 2 else { continue }
            // Fresh first, seen last — a stable partition, so the curated order
            // holds within each half and the shelf keeps its full count.
            let fresh = picks.filter { !shown.contains($0.id) }
            let seen = picks.filter { shown.contains($0.id) }
            let shelved = Array((fresh + seen).prefix(shelfLimit))
            shown.formUnion(shelved.map(\.id))
            sections.append(.shelf(shelf, shelved))
        }

        if !ordered.isEmpty { sections.append(.catalog(ordered)) }
        return sections
    }

    /// The catalog in the order the grid shows it: the new templates first, in
    /// their curated order, then everything else as it was loaded. Ids are
    /// de-duplicated — the grid's data source cannot hold one twice.
    public static func catalogOrder(
        _ templates: [CollageTemplate], curation: CollageGalleryCuration
    ) -> [CollageTemplate] {
        var seen = Set<String>()
        let unique = templates.filter { seen.insert($0.id).inserted }
        let rank = Dictionary(curation.newTemplateIDs.enumerated().map { ($1, $0) },
                              uniquingKeysWith: { first, _ in first })
        let fresh = unique.filter { rank[$0.id] != nil }.sorted { rank[$0.id]! < rank[$1.id]! }
        return fresh + unique.filter { rank[$0.id] == nil }
    }

    static func matches(_ template: CollageTemplate, _ query: CollageGalleryQuery) -> Bool {
        if let category = query.category,
           template.category.caseInsensitiveCompare(category) != .orderedSame { return false }
        guard query.photos.matches(template.photoCount) else { return false }
        if let ratio = query.ratio, CanvasPreset(aspectRatio: template.canvasAspectRatio) != ratio {
            return false
        }
        let search = query.trimmedSearch
        if !search.isEmpty {
            return template.name.localizedCaseInsensitiveContains(search)
                || template.category.localizedCaseInsensitiveContains(search)
        }
        return true
    }
}
