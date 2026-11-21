//
//  CollageGalleryPlannerTests.swift
//  CaroullageTests
//
//  The Collage tab's browse logic as arithmetic (2026-11-21): which shelves
//  show, in what order, when the season's shelf appears, and how a chip, the
//  photo-count filter, the ratio filter and search narrow the catalog. Plus the
//  bundled curation's integrity — a typo there must fail here, not leave a
//  shelf silently short on a user's phone.
//

import XCTest
@testable import Caroullage

@MainActor
final class CollageGalleryPlannerTests: XCTestCase {

    private func template(
        _ id: String, category: String = "grid", ratio: String = "1:1", photos: Int = 2,
        premium: Bool = false, name: String? = nil
    ) throws -> CollageTemplate {
        let cells = (0..<photos).map { i in
            #"{"id":"c\#(i)","type":"photo","frame":{"x":0,"y":\#(Double(i) / Double(photos)),"width":1,"height":\#(1 / Double(photos))},"shape":"rectangle"}"#
        }.joined(separator: ",")
        let json = ##"{"id":"\##(id)","name":"\##(name ?? id)","category":"\##(category)","isPremium":\##(premium),"canvasAspectRatio":"\##(ratio)","cells":[\##(cells)],"background":{"type":"solid","color":"#FFFFFF"}}"##
        return try TemplateParser().parse(data: Data(json.utf8))
    }

    private func shelf(_ id: String, category: String? = nil, ids: [String]? = nil,
                       months: [Int]? = nil) -> CollageGalleryCuration.Shelf {
        .init(id: id, titleKey: id, category: category, templateIDs: ids, months: months)
    }

    // MARK: - Browsing

    func testBrowsingIsSpotlightThenShelvesThenTheWholeCatalog() throws {
        let templates = try [
            template("a", category: "instant"), template("b", category: "instant"),
            template("c", category: "film"), template("d", category: "film"),
        ]
        let curation = CollageGalleryCuration(
            spotlight: ["c", "a"], newTemplateIDs: [],
            shelves: [shelf("instant", category: "instant"), shelf("film", category: "film")])

        let sections = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 6)

        XCTAssertEqual(sections.map(\.id), ["spotlight", "shelf-instant", "shelf-film", "catalog"])
        XCTAssertEqual(sections[0].templates.map(\.id), ["c", "a"], "spotlight keeps its curated order")
        XCTAssertEqual(sections[1].templates.map(\.id), ["b", "a"],
                       "the spotlight already showed a, so the shelf leads with b")
        XCTAssertEqual(sections[3].templates.count, 4, "the catalog closes with everything")
    }

    /// A curation typo (an id listed twice in one row) must not put two
    /// identical items in one diffable section: that crashes the tab.
    func testAnIDListedTwiceInARowAppearsOnce() throws {
        let templates = try [template("a"), template("b"), template("c")]
        let curation = CollageGalleryCuration(
            spotlight: ["a", "b", "a"], newTemplateIDs: [],
            shelves: [shelf("picks", ids: ["c", "b", "c", "a"])])

        let sections = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 6)

        XCTAssertEqual(sections[0].templates.map(\.id), ["a", "b"])
        let shelf = try XCTUnwrap(sections.first { $0.id == "shelf-picks" })
        XCTAssertEqual(Set(shelf.templates.map(\.id)).count, shelf.templates.count)
        XCTAssertEqual(shelf.templates.count, 3)
    }

    func testTheSeasonShelfShowsOnlyInItsMonths() throws {
        let templates = try [template("x", category: "seasonal"), template("y", category: "seasonal")]
        let curation = CollageGalleryCuration(
            spotlight: [], newTemplateIDs: [],
            shelves: [shelf("holiday", category: "seasonal", months: [11, 12, 1])])

        let november = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 11)
        let june = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 6)

        XCTAssertTrue(november.contains { $0.id == "shelf-holiday" })
        XCTAssertFalse(june.contains { $0.id == "shelf-holiday" }, "out of season, the shelf steps aside")
    }

    func testAShelfLeadsWithTemplatesAnEarlierRowDidNotShow() throws {
        let templates = try ["a", "b", "c", "d"].map { try template($0, category: "instant") }
        let curation = CollageGalleryCuration(
            spotlight: ["a"], newTemplateIDs: [],
            shelves: [shelf("trending", ids: ["b", "d"]), shelf("instant", category: "instant")])

        let sections = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 1)

        XCTAssertEqual(sections.first { $0.id == "shelf-instant" }?.templates.map(\.id),
                       ["c", "a", "b", "d"],
                       "unseen first; the ones already shown keep their order at the back")
    }

    func testExplicitIDsWinOverTheCategoryAndUnknownIDsAreSkipped() throws {
        let templates = try [template("a"), template("b"), template("c")]
        let curation = CollageGalleryCuration(
            spotlight: ["missing"], newTemplateIDs: [],
            shelves: [shelf("pick", category: "grid", ids: ["c", "nope", "a"])])

        let sections = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 1)

        XCTAssertFalse(sections.contains { $0.id == "spotlight" }, "a spotlight of nothing is omitted")
        XCTAssertEqual(sections.first { $0.id == "shelf-pick" }?.templates.map(\.id), ["c", "a"])
    }

    func testAShelfOfOneIsDroppedAndAShelfIsCapped() throws {
        var templates = try [template("solo", category: "film")]
        for i in 0..<20 { templates.append(try template("g\(i)")) }
        let curation = CollageGalleryCuration(
            spotlight: [], newTemplateIDs: [],
            shelves: [shelf("film", category: "film"), shelf("grid", category: "grid")])

        let sections = CollageGalleryPlanner.sections(
            templates: templates, curation: curation, query: .init(), month: 1)

        XCTAssertFalse(sections.contains { $0.id == "shelf-film" })
        XCTAssertEqual(sections.first { $0.id == "shelf-grid" }?.templates.count,
                       CollageGalleryPlanner.shelfLimit)
    }

    func testTheCatalogLeadsWithNewTemplatesAndHoldsEachIDOnce() throws {
        let templates = try [template("old1"), template("new2"), template("old2"),
                             template("new1"), template("old1")]
        let curation = CollageGalleryCuration(spotlight: [], newTemplateIDs: ["new1", "new2"], shelves: [])

        let order = CollageGalleryPlanner.catalogOrder(templates, curation: curation).map(\.id)

        XCTAssertEqual(order, ["new1", "new2", "old1", "old2"])
    }

    // MARK: - Finding

    func testAnyNarrowingCollapsesToOneResultsGrid() throws {
        let templates = try [
            template("a", category: "instant", ratio: "4:5", photos: 3),
            template("b", category: "instant", ratio: "9:16", photos: 4),
            template("c", category: "film", ratio: "4:5", photos: 3),
            template("d", category: "dump", ratio: "4:5", photos: 9, name: "Weekend Dump"),
        ]
        let curation = CollageGalleryCuration(
            spotlight: ["a"], newTemplateIDs: [], shelves: [shelf("i", category: "instant")])
        func ids(_ query: CollageGalleryQuery) -> [String] {
            let sections = CollageGalleryPlanner.sections(
                templates: templates, curation: curation, query: query, month: 1)
            XCTAssertLessThanOrEqual(sections.count, 1)
            XCTAssertTrue(sections.allSatisfy { $0.id == "results" })
            return sections.first?.templates.map(\.id) ?? []
        }

        XCTAssertEqual(ids(.init(category: "instant")), ["a", "b"])
        XCTAssertEqual(ids(.init(photos: .three)), ["a", "c"])
        XCTAssertEqual(ids(.init(photos: .sixPlus)), ["d"])
        XCTAssertEqual(ids(.init(ratio: .story)), ["b"])
        XCTAssertEqual(ids(.init(category: "instant", photos: .three)), ["a"])
        XCTAssertEqual(ids(.init(search: "weekend")), ["d"], "search reads the name")
        XCTAssertEqual(ids(.init(search: "FILM")), ["c"], "and the category, without case")
        XCTAssertEqual(ids(.init(category: "film", ratio: .story)), [], "no matches is no sections")
    }

    func testWhitespaceOnlySearchStillBrowses() {
        XCTAssertTrue(CollageGalleryQuery(search: "   ").isBrowsing)
        XCTAssertFalse(CollageGalleryQuery(photos: .one).isBrowsing)
    }

    // MARK: - The bundled curation

    func testTheBundledCurationResolvesAndItsSpotlightIsFree() {
        let bundle = Bundle(for: CollageRenderer.self)
        let curation = CollageGalleryCuration.bundled(in: bundle)
        XCTAssertFalse(curation.spotlight.isEmpty, "collage_gallery.json failed to load or decode")
        XCTAssertFalse(curation.shelves.isEmpty)

        let service = TemplateService(bundle: bundle)
        let byID = Dictionary(service.loadBundledTemplates().map { ($0.id, $0) },
                              uniquingKeysWith: { first, _ in first })

        for id in curation.spotlight {
            let template = byID[id]
            XCTAssertNotNil(template, "spotlight id '\(id)' names no bundled template")
            XCTAssertEqual(template?.isPremium, false,
                           "spotlight '\(id)' is premium — the first card the tab offers must open for anyone")
        }
        for id in curation.newTemplateIDs {
            XCTAssertNotNil(byID[id], "new id '\(id)' names no bundled template")
        }
        let categories = Set(TemplateGalleryViewController.categories.compactMap(\.id))
        for shelf in curation.shelves {
            for id in shelf.templateIDs ?? [] {
                XCTAssertNotNil(byID[id], "shelf '\(shelf.id)' lists unknown template '\(id)'")
            }
            if let category = shelf.category {
                XCTAssertTrue(categories.contains(category),
                              "shelf '\(shelf.id)' See All targets '\(category)', which has no chip")
            }
            XCTAssertEqual(Set(curation.shelves.map(\.id)).count, curation.shelves.count, "shelf ids must be unique")
        }
    }

    func testEveryTemplateCategoryHasAChip() {
        let service = TemplateService(bundle: Bundle(for: CollageRenderer.self))
        let chips = Set(TemplateGalleryViewController.categories.compactMap(\.id))
        for template in service.loadBundledTemplates() {
            XCTAssertTrue(chips.contains(template.category.lowercased()),
                          "\(template.id): category '\(template.category)' is unreachable from the chips")
        }
    }
}
