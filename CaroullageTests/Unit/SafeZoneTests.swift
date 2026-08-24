//
//  SafeZoneTests.swift
//  CaroullageTests
//
//  Step 03b slice 6/8 — safe-zone presets. Regions are authored in 9:16 screen
//  space and projected onto a frame's actual aspect; projected bands must land where
//  the platform UI truly is and never spill outside the frame. Preview-only.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class SafeZoneTests: XCTestCase {

    private let storyAspect: CGFloat = 9.0 / 16.0
    private let commonAspects: [CGFloat] = [9.0 / 16.0, 4.0 / 5.0, 1.0, 16.0 / 9.0]

    func testNonePresetHasNoRegionsAtAnyAspect() {
        for aspect in commonAspects {
            XCTAssertTrue(SafeZonePreset.none.coveredRegions(forFrameAspect: aspect).isEmpty)
        }
    }

    func testEveryPresetIsRepresentedAndNamed() {
        XCTAssertEqual(SafeZonePreset.allCases.count, 5)
        for preset in SafeZonePreset.allCases {
            XCTAssertFalse(preset.displayName.isEmpty)
        }
    }

    func testStoryOnAStoryFrameDimsTopAndBottom() {
        let regions = SafeZonePreset.instagramStory.coveredRegions(forFrameAspect: storyAspect)
        XCTAssertTrue(regions.contains { $0.minY < 0.15 }, "a top band on a full-screen 9:16 frame")
        XCTAssertTrue(regions.contains { $0.maxY > 0.85 }, "a bottom band on a full-screen 9:16 frame")
    }

    func testWiderFeedFrameCoversLessFullScreenChrome() {
        // A 1:1 post is centered with letterbox on a 9:16 story, so the top/bottom
        // story chrome sits OUTSIDE the image — fewer covered regions than 9:16.
        let story = SafeZonePreset.instagramStory
        XCTAssertLessThan(
            story.coveredRegions(forFrameAspect: 1.0).count,
            story.coveredRegions(forFrameAspect: storyAspect).count,
            "a square frame is less covered by full-screen story chrome than a 9:16 frame")
    }

    func testReelsProjectsARightActionRail() {
        let regions = SafeZonePreset.instagramReels.coveredRegions(forFrameAspect: storyAspect)
        XCTAssertTrue(regions.contains { $0.maxX > 0.98 && $0.minX > 0.5 },
                      "the right-hand action rail is present")
    }

    func testAllProjectedRegionsStayWithinTheFrame() {
        for preset in SafeZonePreset.allCases {
            for aspect in commonAspects {
                for region in preset.coveredRegions(forFrameAspect: aspect) {
                    XCTAssertGreaterThanOrEqual(region.minX, -0.0001)
                    XCTAssertGreaterThanOrEqual(region.minY, -0.0001)
                    XCTAssertLessThanOrEqual(region.maxX, 1.0001)
                    XCTAssertLessThanOrEqual(region.maxY, 1.0001)
                    XCTAssertGreaterThan(region.width, 0)
                    XCTAssertGreaterThan(region.height, 0)
                }
            }
        }
    }
}
