//
//  SampleDressingVarietyTests.swift
//  CaroullageTests
//
//  2026-11-21 — the browse tabs sell the catalog with sample photography, and a
//  tab where the same few faces repeat across every card reads as thin, not
//  premium. 178 collage slots and 178 carousel slots had been dressed from 24
//  photos (one beach shot appeared 14 times on the Carousel tab). The pool is
//  now 85 photos, dressed by `Tools/assign_sample_photos.py`. These tests pin
//  the variety rules so a hand-edited manifest cannot slide back.
//

import XCTest
@testable import Caroullage

@MainActor
final class SampleDressingVarietyTests: XCTestCase {

    private var bundle: Bundle { Bundle(for: CollageRenderer.self) }

    private struct Manifest: Decodable {
        struct Template: Decodable { let photos: [String] }
        struct Carousel: Decodable { let framePhotos: [[String]] }
        let templates: [String: Template]
        let carousels: [String: Carousel]
    }

    private func manifest() throws -> Manifest {
        let url = try XCTUnwrap(bundle.url(forResource: "sample_content_manifest", withExtension: "json"))
        return try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
    }

    /// The most cards on one tab any single photo may appear on.
    private let maxCardsPerPhoto = 3

    // MARK: - Collage tab

    func testNoCollageTemplateRepeatsAPhoto() throws {
        for (id, entry) in try manifest().templates {
            XCTAssertEqual(Set(entry.photos).count, entry.photos.count, "\(id) shows the same photo twice")
        }
    }

    func testNoPhotoCarriesTheCollageTab() throws {
        var cards: [String: Int] = [:]
        for entry in try manifest().templates.values {
            for photo in Set(entry.photos) { cards[photo, default: 0] += 1 }
        }
        for (photo, count) in cards {
            XCTAssertLessThanOrEqual(count, maxCardsPerPhoto,
                                     "\(photo) dresses \(count) collage templates")
        }
    }

    // MARK: - Carousel tab

    func testNoCarouselRepeatsAPhotoAcrossItsSlides() throws {
        let types = carouselTypes()
        for (id, entry) in try manifest().carousels {
            switch types[id] {
            case .panoramic:
                // One wide photo, sliced across every slide.
                XCTAssertEqual(Set(entry.framePhotos.flatMap { $0 }).count, 1,
                               "\(id): a panorama is cut from a single photo")
            case .gridPreview:
                // Slide 1 is the grid; each later slide reveals one of its photos.
                let grid = entry.framePhotos.first ?? []
                XCTAssertEqual(Set(grid).count, grid.count, "\(id): the grid repeats a photo")
                XCTAssertEqual(Array(entry.framePhotos.dropFirst()).map { $0.first },
                               grid.map { Optional($0) },
                               "\(id): the reveal slides must follow the grid, in order")
            default:
                let all = entry.framePhotos.flatMap { $0 }
                XCTAssertEqual(Set(all).count, all.count, "\(id) shows the same photo on two slides")
            }
        }
    }

    func testEveryCarouselCoverIsDifferent() throws {
        var covers: [String: String] = [:]
        for (id, entry) in try manifest().carousels {
            guard let cover = entry.framePhotos.first?.first else { continue }
            if let other = covers[cover] {
                XCTFail("\(id) and \(other) open on the same photo, \(cover)")
            }
            covers[cover] = id
        }
    }

    func testNoPhotoCarriesTheCarouselTab() throws {
        var cards: [String: Int] = [:]
        for entry in try manifest().carousels.values {
            for photo in Set(entry.framePhotos.flatMap { $0 }) { cards[photo, default: 0] += 1 }
        }
        for (photo, count) in cards {
            XCTAssertLessThanOrEqual(count, maxCardsPerPhoto, "\(photo) dresses \(count) carousels")
        }
    }

    func testTheCarouselTabShowsEachTemplateOnce() {
        let service = TemplateService(bundle: bundle)
        let sections = CarouselGalleryFilter.sections(
            service.loadBundledCarouselTemplates(), type: nil, ratio: nil, search: "")
        let ids = sections.flatMap { $0.templates.map(\.id) }
        XCTAssertEqual(Set(ids).count, ids.count, "a carousel template appears in two sections")
    }

    private func carouselTypes() -> [String: CarouselType] {
        Dictionary(TemplateService(bundle: bundle).loadBundledCarouselTemplates().map { ($0.id, $0.carouselType) },
                   uniquingKeysWith: { first, _ in first })
    }
}
