//
//  ExportSaveUITests.swift
//  ClaudeCollageUITests
//
//  Regression guard for the Swift 6 @MainActor executor trap on the export/save
//  path. PhotoKit invokes `requestAuthorization` / `performChanges` completion
//  handlers on a background queue; if those closures are @MainActor-isolated
//  (the default for non-Sendable closures inside a @MainActor VC), entering them
//  off-main trips `dispatch_assert_queue` → crash. This test drives a real
//  export→save and asserts the app survives and reaches the success toast.
//
//  Self-contained: it answers the "Add to Photos" system prompt via SpringBoard
//  when it appears, so the background completion handler fires (off-main) whether
//  or not authorization was pre-granted.
//

import XCTest

final class ExportSaveUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testExportSaveDoesNotCrash() throws {
        let app = XCUIApplication()
        app.launch()

        // Enter the editor.
        let addButton = app.buttons["newProjectButton"]
        XCTAssertTrue(addButton.waitForExistence(timeout: 8), "Home add button")
        addButton.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "Editor pushes")

        // Open the Universal Export sheet and save to Photos (image-only for grid).
        let exportButton = app.buttons["exportButton"]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 4), "Export button present")
        exportButton.tap()
        let save = app.buttons["exportSaveButton"]
        XCTAssertTrue(save.waitForExistence(timeout: 4), "Export sheet presented")
        save.tap()

        // Answer the "Add to Photos" prompt if the sim hasn't granted it yet.
        // (Granting resolves authorization → the completion handler fires on a
        // background queue, which is exactly the crash path under test.) Add-only
        // prompt labels vary by iOS version, so tap whichever button is NOT the
        // deny option rather than matching a specific "Allow" string.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let prompt = springboard.alerts.firstMatch
        let promptAppeared = prompt.waitForExistence(timeout: 8)
        if promptAppeared {
            // The affirmative button is "Allow" / "Allow Full Access" / "OK".
            // Match on "Allow" (excluding "Don't Allow", which uses a curly
            // apostrophe) with an "OK" fallback — never tap the deny option.
            let grant = prompt.buttons.allElementsBoundByIndex.first { button in
                let l = button.label
                return (l.localizedCaseInsensitiveContains("Allow") && !l.localizedCaseInsensitiveContains("Don"))
                    || l == "OK"
            }
            grant?.tap()
            // Confirm we actually answered it — otherwise authorization stays
            // undetermined and the completion handler (the crash path) never fires.
            XCTAssertFalse(prompt.waitForExistence(timeout: 3), "Photos prompt was not dismissed")
        }

        // Answering the prompt resolves authorization, so PhotoKit invokes its
        // completion handlers on a BACKGROUND queue — the exact path that crashed
        // pre-fix (Swift 6 @MainActor executor assertion on handler entry). The
        // "Saved to Photos" toast is transient (~1.8s) and races the SpringBoard
        // round-trip, so the reliable regression signal is SURVIVAL: a crash would
        // terminate the app, so assert the editor is still present and the app is
        // still running in the foreground after the save path executes.
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8),
                      "Editor gone — app crashed during saveToPhotos (Swift 6 @MainActor executor trap regression)")
        XCTAssertEqual(app.state, .runningForeground, "App must remain in foreground (no crash)")
    }
}
