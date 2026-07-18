//
//  SafeZoneTests.swift
//  ClaudeCollageTests
//
//  Step 03b slice 6 — the safe-zone presets that dim the regions where each
//  platform's UI (status bar, caption, action rail) would cover a carousel frame in
//  the preview. Pure normalized geometry; the overlay is preview-only and never
//  exported.
//

import XCTest
import CoreGraphics
@testable import ClaudeCollage

final class SafeZoneTests: XCTestCase {

    func testNonePresetHasNoCoveredRegions() {
        XCTAssertTrue(SafeZonePreset.none.coveredRegions.isEmpty)
    }

    func testEveryPresetIsRepresentedAndNamed() {
        // All four platform presets plus "none".
        XCTAssertEqual(SafeZonePreset.allCases.count, 5)
        for preset in SafeZonePreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }

    func testPlatformPresetsCoverTopOrBottomBands() {
        for preset in [SafeZonePreset.instagramStory, .instagramReels, .tiktok, .generic] {
            XCTAssertFalse(preset.coveredRegions.isEmpty, "\(preset) should dim at least one region")
        }
    }

    func testAllRegionsStayWithinTheUnitSquare() {
        for preset in SafeZonePreset.allCases {
            for region in preset.coveredRegions {
                XCTAssertGreaterThanOrEqual(region.minX, 0)
                XCTAssertGreaterThanOrEqual(region.minY, 0)
                XCTAssertLessThanOrEqual(region.maxX, 1.0001)
                XCTAssertLessThanOrEqual(region.maxY, 1.0001)
                XCTAssertGreaterThan(region.width, 0)
                XCTAssertGreaterThan(region.height, 0)
            }
        }
    }

    func testStoryDimsTopAndBottom() {
        let regions = SafeZonePreset.instagramStory.coveredRegions
        XCTAssertTrue(regions.contains { $0.minY < 0.15 }, "a top band")
        XCTAssertTrue(regions.contains { $0.maxY > 0.85 }, "a bottom band")
    }
}
