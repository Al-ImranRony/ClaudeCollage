//
//  AppStoreScreenshotUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.7. The App Store screenshots, captured by the same suite
//  that tests the app: `-ScreenshotMode` fills the editors with the bundled
//  sample photography, the language comes from the SCREENSHOT_LANGUAGE
//  environment variable (Tools/screenshots.sh loops the eleven), and each
//  scene is attached as `store-<n>-<scene>` for Tools/screenshots.sh to export
//  and Tools/ScreenshotFramer to caption.
//
//  Scenes follow the brief's five. The fifth — the subject lift before/after —
//  needs Vision, which the simulator does not run, so it is captured on a
//  device; here the fifth scene is the video collage's timeline instead, and
//  the brief's Home showcase stands in as a sixth.
//

import XCTest

final class AppStoreScreenshotUITests: XCTestCase {

    private var language: String {
        ProcessInfo.processInfo.environment["SCREENSHOT_LANGUAGE"] ?? "en"
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments += ["-hasSeenOnboarding", "YES", "-UITestMode", "1", "-ScreenshotMode", "1",
                                "-AppleLanguages", "(\(language))", "-AppleLocale", language]
        app.launch()
        return app
    }

    @MainActor
    private func capture(_ index: Int, _ scene: String, of app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "store-\(index)-\(scene)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testCaptureEveryStoreScene() throws {
        let app = launch()
        // Tab buttons are looked up app-wide: on iPadOS the tab controller
        // renders as the top tab bar, which is not an XCUI `TabBar`.
        XCTAssertTrue(app.buttons["startEditingButton"].waitForExistence(timeout: 10))

        // 1 — Carousel: the editor with its filled frames, then the preview.
        app.openCarouselTypePicker()
        app.buttons["carouselType-matched"].tap()
        app.buttons["carouselCreateButton"].tap()
        XCTAssertTrue(app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 10))
        sleep(1)   // thumbnails render off the main thread
        capture(1, "carousel", of: app)
        app.navigationBars.buttons.firstMatch.tap()

        // 2 — Shapes: a hexagon collage, filled.
        XCTAssertTrue(app.buttons["polygonQuickStartButton"].waitForExistence(timeout: 8))
        app.buttons["polygonQuickStartButton"].tap()
        XCTAssertTrue(app.navigationBars.element.waitForExistence(timeout: 8))
        sleep(1)
        capture(2, "shapes", of: app)
        app.navigationBars.buttons.firstMatch.tap()

        // 3 — The template gallery.
        // `firstMatch`: iPadOS lists a tab in both its top bar and its sidebar.
        XCTAssertTrue(app.buttons["templatesButton"].firstMatch.waitForExistence(timeout: 8))
        app.buttons["templatesButton"].firstMatch.tap()
        XCTAssertTrue(app.collectionViews["templateGalleryGrid"].waitForExistence(timeout: 10))
        sleep(1)
        capture(3, "templates", of: app)
        app.buttons["homeTab"].firstMatch.tap()

        // 4 — Video collage: the editor with its clips.
        XCTAssertTrue(app.buttons["videoCollageButton"].waitForExistence(timeout: 8))
        app.buttons["videoCollageButton"].tap()
        XCTAssertTrue(app.otherElements["videoTimeline"].waitForExistence(timeout: 10))
        sleep(2)   // the player's first frame
        capture(4, "video", of: app)

        // 5 — The same, timeline expanded.
        app.buttons["videoTimelineChevron"].tap()
        sleep(1)
        capture(5, "video-timeline", of: app)
        app.navigationBars.buttons.firstMatch.tap()

        // 6 — Home's showcase.
        XCTAssertTrue(app.collectionViews["heroShowcase"].waitForExistence(timeout: 8))
        sleep(1)
        capture(6, "home", of: app)
    }
}
