//
//  VideoEditorUITests.swift
//  CaroullageUITests
//
//  Step 04 slice 5b — the video collage editor: entry from Home, the AVPlayerLayer
//  canvas with one tappable slot per layout cell, the always-visible Export button,
//  and switching layouts. Picking an actual clip goes through the system PHPicker,
//  so that stays manual QA — these tests cover the wiring around it.
//

import XCTest

final class VideoEditorUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    private func openVideoEditor(_ app: XCUIApplication) {
        app.launch()
        let video = app.buttons["videoCollageButton"]
        XCTAssertTrue(video.waitForExistence(timeout: 8), "Home shows the Video Collage button")
        video.tap()
        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8),
                      "Video editor pushes")
    }

    @MainActor
    func testVideoEditorOpensWithCanvasAndControls() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)

        XCTAssertTrue(app.otherElements["videoCanvas"].waitForExistence(timeout: 5),
                      "The AVPlayerLayer canvas is shown")
        // The default layout is a 2-up vertical stack → two tappable slots.
        // Slots are buttons since phase 6.5 — VoiceOver names and presses them —
        // so they are queried as what they are, not as bare containers.
        XCTAssertTrue(app.buttons["videoCell-0"].exists, "Slot 0 is present")
        XCTAssertTrue(app.buttons["videoCell-1"].exists, "Slot 1 is present")
        // Export must be reachable at any point during editing (Step 04 done-criteria).
        XCTAssertTrue(app.buttons["videoExportButton"].exists, "Export is always visible")
        XCTAssertTrue(app.buttons["videoLayoutButton"].exists, "Layout control is present")
        XCTAssertTrue(app.buttons["videoMusicButton"].exists, "Music control is present")
    }

    @MainActor
    func testVideoCollageResumesFromHome() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)
        // Switch to a 4-up grid so the resumed project is distinguishable from a
        // fresh one (which starts as a 2-up stack).
        app.buttons["videoLayoutButton"].tap()
        let fourUp = app.buttons["4 · Grid"]
        XCTAssertTrue(fourUp.waitForExistence(timeout: 5))
        fourUp.tap()
        XCTAssertTrue(app.buttons["videoCell-3"].waitForExistence(timeout: 5))

        // Back out of the editor, then over to the Projects tab: the saved gallery
        // lives there since Home became a discovery screen (Step 04.5 batch C).
        app.navigationBars["Video Collage"].buttons.element(boundBy: 0).tap()
        XCTAssertTrue(app.navigationBars["Caroullage"].waitForExistence(timeout: 8))

        app.buttons["projectsTab"].tap()
        let card = app.collectionViews["projectsGrid"].cells.element(boundBy: 0)
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Projects shows the saved video collage")
        card.tap()

        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8),
                      "Reopening resumes the video editor")
        XCTAssertTrue(app.buttons["videoCell-3"].waitForExistence(timeout: 5),
                      "The 4-up layout resumed intact")
    }

    @MainActor
    func testAddingTextPlacesAnEditableOverlay() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)
        XCTAssertTrue(app.buttons["videoAddTextButton"].waitForExistence(timeout: 5),
                      "the add-text button is present")
        XCTAssertTrue(app.buttons["videoAddStickerButton"].exists, "the add-sticker button is present")

        app.buttons["videoAddTextButton"].tap()
        // Adding text opens the style sheet immediately (its Done button appears).
        XCTAssertTrue(app.buttons["Done"].waitForExistence(timeout: 5),
                      "the text style sheet opens for the new overlay")
    }

    // MARK: - The redesigned chrome (Plan 1 Task 6 / Plan 2)
    //
    // The unit suites build this controller in a synthetic window; these prove it
    // survives the real app — navigation, hidden tab bar, safe areas. That
    // distinction has mattered here: Plan 1 shipped a tool rail with a ZERO
    // HEIGHT hit target that every unit test passed, and Task 6 briefly shipped a
    // video editor with no way to pause at all. Both are asserted below.

    @MainActor
    func testTheEditorBottomIsAFiveToolRail() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)

        for id in ["videoLayoutButton", "videoFrameTool", "videoAddTextButton",
                   "videoAddStickerButton", "videoMusicButton"] {
            let tool = app.buttons[id]
            XCTAssertTrue(tool.waitForExistence(timeout: 5), "\(id) is on the rail")
            XCTAssertTrue(tool.isHittable, "\(id) must be tappable, not merely present")
        }
    }

    @MainActor
    func testAToolOpensAPanelThatClosesAgain() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)

        let frameTool = app.buttons["videoFrameTool"]
        XCTAssertTrue(frameTool.waitForExistence(timeout: 5))
        frameTool.tap()

        let close = app.buttons["editorPanelCloseButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5), "the Frame panel opens")
        XCTAssertTrue(close.isHittable, "its close button is a real hit target")
        close.tap()
        XCTAssertFalse(close.waitForExistence(timeout: 2), "and the panel closes again")
    }

    @MainActor
    func testThePreviewCanAlwaysBePaused() {
        // Task 6 removed the toolbar Play button and made the preview autoplay,
        // leaving nothing on screen to stop it. The timeline owns that control now.
        let app = XCUIApplication.underTest()
        openVideoEditor(app)

        let playback = app.buttons["videoPlayButton"]
        XCTAssertTrue(playback.waitForExistence(timeout: 5),
                      "a playback control must be reachable without expanding anything")
        XCTAssertTrue(playback.isHittable)
    }

    @MainActor
    func testTheTimelineIsCollapsedByDefaultAndExpands() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)

        let timeline = app.otherElements["videoTimeline"]
        XCTAssertTrue(timeline.waitForExistence(timeout: 5), "the timeline is on screen")
        let collapsed = timeline.frame.height
        XCTAssertGreaterThan(collapsed, 0,
                             "a zero-height timeline would be invisible and untappable — the " +
                             "exact bug a unit test cannot see")

        let chevron = app.buttons["videoTimelineChevron"]
        XCTAssertTrue(chevron.isHittable, "the expand control is a real hit target")
        chevron.tap()

        // The expansion is animated, so give the layout a bounded moment to land
        // rather than asserting on the frame mid-transition.
        let deadline = Date().addingTimeInterval(5)
        while timeline.frame.height <= collapsed, Date() < deadline {
            usleep(100_000)
        }
        XCTAssertGreaterThan(timeline.frame.height, collapsed,
                             "tapping the chevron expands the timeline into its lanes")
    }

    @MainActor
    func testChangingLayoutChangesSlotCount() {
        let app = XCUIApplication.underTest()
        openVideoEditor(app)
        XCTAssertTrue(app.buttons["videoCell-1"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["videoCell-3"].exists, "2-up starts with two slots")

        app.buttons["videoLayoutButton"].tap()
        let fourUp = app.buttons["4 · Grid"]
        XCTAssertTrue(fourUp.waitForExistence(timeout: 5), "Layout sheet lists the grids")
        fourUp.tap()

        XCTAssertTrue(app.buttons["videoCell-3"].waitForExistence(timeout: 5),
                      "Switching to the 4-up grid adds slots")
    }
}
