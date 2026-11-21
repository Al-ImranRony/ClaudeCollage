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
            let blank = app.buttons["videoBlank-4:5"]   // the start sheet
            XCTAssertTrue(blank.waitForExistence(timeout: 10))
            blank.tap()
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

// MARK: - Scrolling (2026-11-20)
//
// Hitch time ratio while flinging the two browse surfaces, from a COLD preview
// cache (`-ColdPreviewCache`): the first iteration renders every card it meets
// from sample photography, which is the first-launch experience. Later
// iterations measure the warm path. Lower is better; Apple's guidance is
// < 5 ms/s "good", > 10 ms/s "critical".
extension PerformanceUITests {

    @MainActor
    private func launchCold() -> XCUIApplication {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-ColdPreviewCache", "1", "-FrameProbe", "1"]
        app.launch()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 10))
        return app
    }

    /// Taps the probe, which drives the screen's main scroll view down and
    /// back up by itself (no XCUITest activity inside the measured window),
    /// waits it out, and returns the probe's report.
    @MainActor
    private func drive(_ app: XCUIApplication) -> [String: Double] {
        let probe = app.buttons["frameDropProbe"]
        XCTAssertTrue(probe.waitForExistence(timeout: 5))
        probe.tap()
        sleep(9)   // longer than the longest drive
        var raw = probe.value as? String ?? ""
        for _ in 0..<10 where !raw.hasPrefix("done") {
            sleep(2)
            raw = probe.value as? String ?? ""
        }
        XCTAssertTrue(raw.hasPrefix("done"), "probe never finished: \(raw)")
        var out: [String: Double] = [:]
        for pair in raw.split(separator: " ") {
            let parts = pair.split(separator: "=")
            if parts.count == 2, let value = Double(parts[1]) { out[String(parts[0])] = value }
        }
        return out
    }

    /// Drive 0 runs on a cold preview cache (the down pass renders every card
    /// it meets); drives 1–2 are warm. The up pass of every drive is warm.
    @MainActor
    private func measureDrives(in app: XCUIApplication, label: String) {
        var lines: [String] = []
        for round in 0..<3 {
            sleep(round == 0 ? 2 : 1)
            let r = drive(app)
            lines.append(String(
                format: "%@ drive %d: down %.0f ms hitch / %.0f frames (%.0f severe), up %.0f ms / %.0f frames (%.0f severe)",
                label, round, r["downHitchMs"] ?? -1, r["downFrames"] ?? -1, r["downSevere"] ?? -1,
                r["upHitchMs"] ?? -1, r["upFrames"] ?? -1, r["upSevere"] ?? -1))
        }
        let report = lines.joined(separator: "\n")
        print("FRAMEPROBE\n" + report)
        let attachment = XCTAttachment(string: report)
        attachment.name = "\(label) frame probe"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCarouselTabScrollHitches() throws {
        let app = launchCold()
        app.buttons["carouselButton"].tap()
        let grid = app.collectionViews["carouselTemplateGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        measureDrives(in: app, label: "Carousel tab")
    }

    /// The Collage tab browses as a spotlight and sideways shelves over a
    /// vertical page (2026-11-21) — the drive scrolls the page through all of
    /// them and into the catalog grid, cold caches first.
    @MainActor
    func testCollageTabScrollHitches() throws {
        let app = launchCold()
        app.buttons["templatesButton"].tap()
        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 8))
        measureDrives(in: app, label: "Collage tab")
    }

    @MainActor
    func testHomeScrollHitches() throws {
        let app = launchCold()
        let collections = app.otherElements["homeCollections"]
        XCTAssertTrue(collections.waitForExistence(timeout: 8))
        measureDrives(in: app, label: "Home")
    }
}
