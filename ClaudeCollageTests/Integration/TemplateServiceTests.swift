//
//  TemplateServiceTests.swift
//  ClaudeCollageTests
//
//  Step 03a — integration coverage for `TemplateService`: bundled catalog load,
//  thumbnail generation timing, and the premium gate. Uses the app bundle so the
//  real bundled template JSON is exercised.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

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
}
