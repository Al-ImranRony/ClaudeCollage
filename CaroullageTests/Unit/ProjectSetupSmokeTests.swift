//
//  ProjectSetupSmokeTests.swift
//  CaroullageTests
//
//  Step 00 smoke test — confirms the unit test target builds and runs.
//  No real assertions yet; Step 01 begins testing CollageLayoutEngine.
//

import XCTest
@testable import Caroullage

final class ProjectSetupSmokeTests: XCTestCase {

    func testTestTargetBuilds() {
        XCTAssertTrue(true, "If this runs, the unit test target is wired up correctly.")
    }

    func testCollageEnumsAreDefined() {
        XCTAssertEqual(CollageMode.allCases.count, 5)
        XCTAssertEqual(CarouselType.allCases.count, 4)
        XCTAssertEqual(CellShape.allCases.count, 7)
    }

    func testExportSettingsDefaults() {
        let settings = ExportSettings()
        XCTAssertEqual(settings.platform, .instagramPost)
        XCTAssertEqual(settings.imageFormat, .jpeg)
        XCTAssertEqual(settings.videoCodec, .h264)
        XCTAssertTrue(settings.includeWatermark)
    }
}
