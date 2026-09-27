//
//  VideoTemplatesUITests.swift
//  CaroullageUITests
//
//  The new-video sheet and the video templates it opens (2026-09-27). The
//  capture test fills every template with the bundled sample loops
//  (`-ScreenshotMode`) and attaches a frame of each — run it on an iOS 26.x
//  simulator: the iOS 27.0 simulator cannot display an AVVideoComposition, so
//  its editor canvas is blank there (see the build notes).
//

import XCTest

final class VideoTemplatesUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private static let templateIDs = ["title-grid", "lyric-stack", "caption-stack", "travel-filmstrip"]

    @MainActor
    private func openStartSheet(_ app: XCUIApplication) {
        let video = app.buttons["videoCollageButton"]
        XCTAssertTrue(video.waitForExistence(timeout: 10), "Home shows the Video Collage button")
        video.tap()
        XCTAssertTrue(app.buttons["videoTemplate-title-grid"].waitForExistence(timeout: 8),
                      "Video opens the new-video sheet")
    }

    @MainActor
    private func attach(_ name: String, _ app: XCUIApplication) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    @MainActor
    func testTheSheetOffersEveryTemplateAndEveryBlankShape() {
        let app = XCUIApplication.underTest()
        app.launch()
        openStartSheet(app)

        for id in Self.templateIDs {
            XCTAssertTrue(app.buttons["videoTemplate-\(id)"].exists, "\(id) is offered")
        }
        for ratio in ["9:16", "4:5", "1:1", "16:9"] {
            // The blank row can sit below the fold on a small phone.
            let tile = app.buttons["videoBlank-\(ratio)"]
            if !tile.isHittable { app.swipeUp() }
            XCTAssertTrue(tile.exists, "a blank \(ratio) canvas is offered")
        }
        attach("video-start-sheet", app)
    }

    @MainActor
    func testATemplateOpensTheEditorWithItsSlotsAndCaptions() {
        let app = XCUIApplication.underTest()
        app.launch()
        openStartSheet(app)
        app.buttons["videoTemplate-lyric-stack"].tap()

        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8))
        for index in 0 ..< 3 {
            XCTAssertTrue(app.buttons["videoCell-\(index)"].exists, "three rows → slot \(index)")
        }
        XCTAssertFalse(app.buttons["videoCell-3"].exists)
    }

    @MainActor
    func testABlankStoryCanvasOpensTall() {
        let app = XCUIApplication.underTest()
        app.launch()
        openStartSheet(app)
        let story = app.buttons["videoBlank-9:16"]
        if !story.isHittable { app.swipeUp() }
        story.tap()

        let canvas = app.otherElements["videoCanvas"]
        XCTAssertTrue(canvas.waitForExistence(timeout: 8))
        XCTAssertGreaterThan(canvas.frame.height, canvas.frame.width * 1.6, "a 9:16 canvas")
    }

    @MainActor
    func testCaptionMotionIsChosenFromTheTextTools() {
        let app = XCUIApplication.underTest()
        app.launch()
        openStartSheet(app)
        app.buttons["videoTemplate-caption-stack"].tap()
        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8))

        // The template's first caption is on screen at the playhead (0s).
        let caption = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "How to make")).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 5), "the template's caption is on the canvas")
        caption.tap()
        let motion = app.buttons["motionTextTool"]
        XCTAssertTrue(motion.waitForExistence(timeout: 5), "selecting a caption offers Motion")
        motion.tap()
        let wordFade = app.buttons["textAnimation_wordFade"]
        XCTAssertTrue(wordFade.waitForExistence(timeout: 5))
        XCTAssertTrue(wordFade.isSelected, "the Motion panel opens on the caption's own animation")
        app.buttons["textAnimation_pop"].tap()
        XCTAssertTrue(app.buttons["textAnimation_pop"].isSelected)
        attach("video-motion-panel", app)
    }

    /// Visual QA: each template filled with the sample loops, a moment in.
    @MainActor
    func testCaptureEveryTemplateFilled() {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-ScreenshotMode", "1"]
        app.launch()
        for id in Self.templateIDs {
            openStartSheet(app)
            attach("start-\(id)", app)
            app.buttons["videoTemplate-\(id)"].tap()
            XCTAssertTrue(app.otherElements["videoTimeline"].waitForExistence(timeout: 10))
            let play = app.buttons["videoPlayButton"]
            if play.waitForExistence(timeout: 5) { play.tap() }
            sleep(1)
            attach("template-\(id)-1s", app)
            sleep(2)
            attach("template-\(id)-3s", app)
            app.navigationBars.buttons.firstMatch.tap()
            _ = app.buttons["videoCollageButton"].waitForExistence(timeout: 10)
        }
    }
}
