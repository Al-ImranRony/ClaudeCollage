//
//  PerformanceUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.10. The brief's metrics are Instruments-on-hardware work
//  (Allocations, Core Animation, Leaks, Time Profiler, Energy) and belong to
//  the owner's device pass. What this file leaves behind are the two the
//  suite can measure itself, on the simulator today and on a device from
//  Xcode later, as XCTest metrics with a stored baseline:
//
//   • cold launch to the tab shell (`XCTApplicationLaunchMetric`) — the
//     brief's "< 2.0s on iPhone 13" is judged on a device, but a regression
//     shows here first;
//   • memory through the video editor with three clips playing
//     (`XCTMemoryMetric`) — the brief's "< 200 MB" ceiling, watched.
//
//  Baselines are recorded in Xcode's Report navigator on the first run and
//  committed with the .xcbaseline; a run that regresses past them fails.
//  Numbers from the simulator are not the device's; the trend is.
//

import XCTest

final class PerformanceUITests: XCTestCase {

    @MainActor
    func testColdLaunchToTheTabShell() throws {
        let app = XCUIApplication.underTest()
        measure(metrics: [XCTApplicationLaunchMetric()]) {
            app.launch()
            _ = app.tabBars["mainTabBar"].waitForExistence(timeout: 10)
        }
    }

    @MainActor
    func testMemoryThroughTheVideoEditorWithClipsPlaying() throws {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-ScreenshotMode", "1"]   // the editor opens with the bundled loops in place
        measure(metrics: [XCTMemoryMetric(application: app)]) {
            app.launch()
            let video = app.buttons["videoCollageButton"]
            XCTAssertTrue(video.waitForExistence(timeout: 10))
            video.tap()
            XCTAssertTrue(app.otherElements["videoTimeline"].waitForExistence(timeout: 10))
            app.buttons["videoTimelineChevron"].tap()
            sleep(3)   // three loops decoding and compositing
            app.navigationBars.buttons.firstMatch.tap()
            _ = app.tabBars["mainTabBar"].waitForExistence(timeout: 10)
            // The metric samples the app at the end of the block; a terminated
            // app has nothing to sample. The next iteration's launch replaces it.
        }
    }
}
