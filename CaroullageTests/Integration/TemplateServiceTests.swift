//
//  TemplateServiceTests.swift
//  CaroullageTests
//
//  Step 03a — integration coverage for `TemplateService`: bundled catalog load,
//  thumbnail generation timing, and the premium gate. Uses the app bundle so the
//  real bundled template JSON is exercised.
//

import XCTest
import CoreGraphics
@testable import Caroullage

@MainActor
final class TemplateServiceTests: XCTestCase {

    /// The app bundle (where template JSON resources live), resolved via an app class.
    private var appBundle: Bundle { Bundle(for: CollageRenderer.self) }

    private func makeTemplate(_ json: String) throws -> CollageTemplate {
        try TemplateParser().parse(data: Data(json.utf8))
    }

    func testBundledTemplatesLoadOnInit() {
        let service = TemplateService(bundle: appBundle)
        let loaded = service.loadBundledTemplates()
        XCTAssertFalse(loaded.isEmpty, "Expected at least one bundled template to parse")
        XCTAssertEqual(loaded.count, service.templates.count)
        // The JSON Schema file must never be mistaken for a template.
        XCTAssertFalse(loaded.contains { $0.id == "template_schema" })
    }

    func testThumbnailGenerationCompletesWithinTimeout() throws {
        let template = try makeTemplate("""
        {
          "id": "thumb-test", "name": "Thumb", "category": "grid", "isPremium": false,
          "canvasAspectRatio": "1:1",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.0, "width": 0.5, "height": 1.0 } },
            { "id": "c2", "type": "photo", "shape": "circle",
              "frame": { "x": 0.5, "y": 0.0, "width": 0.5, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """)

        let service = TemplateService(bundle: appBundle)
        let start = Date()
        let thumb = service.thumbnail(for: template, maxDimension: 300)
        let elapsed = Date().timeIntervalSince(start)

        let image = try XCTUnwrap(thumb, "Thumbnail render returned nil")
        XCTAssertLessThanOrEqual(elapsed, 2.0, "Thumbnail took \(elapsed)s (budget 2s)")
        XCTAssertEqual(max(image.width, image.height), 300)
    }

    func testPremiumTemplateBlockedForFreeUser() throws {
        let store = EntitlementStore.shared
        let prior = store.isPremiumUnlocked
        defer { store.setPremiumUnlocked(prior) }

        let premium = try makeTemplate("""
        {
          "id": "pro-1", "name": "Pro", "category": "minimal", "isPremium": true,
          "canvasAspectRatio": "4:5",
          "cells": [
            { "id": "c1", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.0, "y": 0.0, "width": 1.0, "height": 1.0 } }
          ],
          "background": { "type": "solid", "color": "#FFFFFF" }
        }
        """)

        let service = TemplateService(bundle: appBundle, entitlements: store)

        store.setPremiumUnlocked(false)
        XCTAssertTrue(service.isPremium(premium))
        XCTAssertFalse(service.canOpen(premium), "Free user must not open a premium template")

        store.setPremiumUnlocked(true)
        XCTAssertTrue(service.canOpen(premium), "Unlocked user should open a premium template")
    }

    // MARK: - Step 03a slice 5: text zones

    /// A photo+text template must route through the `.template` editor path (its
    /// text zone stops it matching a pure photo grid) and expose its text zones as
    /// seedable overlays with normalized frames.
    func testTextTemplateSeedsOverlaysAndRoutesToTemplateLayout() throws {
        let template = try makeTemplate("""
        {
          "id": "story-x", "name": "Story X", "category": "story", "isPremium": false,
          "canvasAspectRatio": "9:16",
          "cells": [
            { "id": "hero", "type": "photo", "shape": "rectangle",
              "frame": { "x": 0.06, "y": 0.06, "width": 0.88, "height": 0.5 } },
            { "id": "headline", "type": "text", "shape": "rectangle",
              "frame": { "x": 0.08, "y": 0.62, "width": 0.84, "height": 0.14 },
              "text": "Your Story", "fontName": "AvenirNext-Bold", "fontSize": 120,
              "color": "#FFFFFF", "alignment": "center" }
          ],
          "background": { "type": "solid", "color": "#161618" }
        }
        """)

        // Seeded overlays come from the parser's text zones.
        let overlays = template.cells.compactMap(\.textStyle)
        XCTAssertEqual(overlays.count, 1)
        XCTAssertEqual(overlays[0].text, "Your Story")
        XCTAssertEqual(overlays[0].fontName, "AvenirNext-Bold")
        XCTAssertEqual(overlays[0].colorHex, "#FFFFFF")

        // A text zone means it is not a pure photo grid → `.template` editor path.
        XCTAssertNil(TemplateService.gridTemplate(matching: template))
        let layout = TemplateService.editorLayout(for: template)
        XCTAssertEqual(layout.cells.count, 1, "Only the photo zone becomes an editor cell")

        // The render request carries the text overlays so the thumbnail previews them.
        let service = TemplateService(bundle: appBundle)
        let request = service.renderRequest(for: template, maxDimension: 300)
        XCTAssertEqual(request.textOverlays.count, 1)
        XCTAssertGreaterThan(request.textFontScale, 0)
        XCTAssertNotNil(service.thumbnail(for: template), "Text template thumbnail must render")
    }

    func testThumbnailFingerprintTracksContentChanges() throws {
        let original = try makeTemplate("""
        { "id": "fp", "name": "FP", "canvasAspectRatio": "1:1",
          "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 0.5, "height": 1 } }] }
        """)
        let sameContent = try makeTemplate("""
        { "id": "fp", "name": "Renamed But Same Look", "canvasAspectRatio": "1:1",
          "cells": [{ "type": "photo", "frame": { "x": 0, "y": 0, "width": 0.5, "height": 1 } }] }
        """)
        let movedCell = try makeTemplate("""
        { "id": "fp", "name": "FP", "canvasAspectRatio": "1:1",
          "cells": [{ "type": "photo", "frame": { "x": 0.1, "y": 0, "width": 0.5, "height": 1 } }] }
        """)

        // Deterministic across template instances (unlike seeded Hashable) …
        XCTAssertEqual(
            TemplateService.contentFingerprint(of: original),
            TemplateService.contentFingerprint(of: sameContent),
            "Fingerprint covers rendered appearance, not the display name"
        )
        // … and changes when the rendered geometry changes, busting stale
        // on-disk thumbnails for re-authored templates.
        XCTAssertNotEqual(
            TemplateService.contentFingerprint(of: original),
            TemplateService.contentFingerprint(of: movedCell)
        )
    }

    // MARK: - Step 03b slice 2: bundled carousel templates

    /// The bundled carousel catalog loads from its own subdirectory, is kept
    /// separate from the standard template gallery, and never mistakes the JSON
    /// schema for a template.
    func testCarouselTemplatesLoadFromBundle() {
        let service = TemplateService(bundle: appBundle)
        let loaded = service.loadBundledCarouselTemplates()
        XCTAssertGreaterThanOrEqual(loaded.count, 15,
            "Expected at least 15 bundled carousel templates, found \(loaded.count)")
        XCTAssertEqual(loaded.count, service.carouselTemplates.count)
        XCTAssertFalse(loaded.contains { $0.id == "carousel_schema" },
            "The JSON Schema file must never be parsed as a carousel template")
        // Every bundled carousel declares a valid type and 2–10 frames.
        for template in loaded {
            XCTAssertTrue((2...10).contains(template.frameCount),
                "\(template.id) frameCount \(template.frameCount) out of range")
            XCTAssertEqual(template.frames.count, template.frameCount,
                "\(template.id) frames array must match its declared frameCount")
        }
        // Carousel templates must not leak into the standard photo-template gallery.
        let standardIDs = Set(service.loadBundledTemplates().map(\.id))
        XCTAssertTrue(loaded.allSatisfy { !standardIDs.contains($0.id) })
    }

    func testAllFourCarouselTypesRepresentedInBundle() {
        let service = TemplateService(bundle: appBundle)
        let types = Set(service.loadBundledCarouselTemplates().map(\.carouselType))
        XCTAssertEqual(types, Set(CarouselType.allCases),
            "The bundle should ship at least one template of every carousel type")
    }
}
