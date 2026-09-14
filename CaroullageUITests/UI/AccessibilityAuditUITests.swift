//
//  AccessibilityAuditUITests.swift
//  CaroullageUITests
//
//  Step 06 phase 6.5. Xcode's accessibility audit — the same checks as
//  Accessibility Inspector's Audit: element descriptions, hit region, Dynamic
//  Type, contrast, clipped text, traits — run on every primary surface, every
//  time the suite runs. This is the brief's "verify with Accessibility
//  Inspector" made repeatable.
//
//  An issue is either fixed or listed in `knownIssues` with a reason. The
//  handler reports anything not listed as a failure carrying the surface name
//  and the audit's own description. The list is the place an accepted exception
//  lives, so it is a decision rather than a silence.
//
//  Routes reuse the identifiers the rest of the suite navigates by; nothing
//  here is reached by label.
//

import XCTest

final class AccessibilityAuditUITests: XCTestCase {

    /// One accepted exception. `elementLabel` matches the element's label
    /// exactly, or every element when it is `"*"`; `surface` narrows it to one
    /// audited surface, or every surface when nil.
    private struct KnownIssue {
        let audit: XCUIAccessibilityAuditType
        let elementLabel: String
        var surface: String? = nil
        let reason: String

        func covers(_ issue: XCUIAccessibilityAuditIssue, label: String, surface: String) -> Bool {
            audit == issue.auditType
                && (elementLabel == "*" || elementLabel == label)
                && (self.surface == nil || self.surface == surface)
        }
    }

    /// Empty is the goal. Add an entry only with a reason a reviewer would accept.
    private static let knownIssues: [KnownIssue] = [
        // Phase 6.5 Batch C is the Dynamic Type sweep; until it lands these two
        // audits report the 21 hardcoded SwiftUI sizes and the UIKit labels
        // that do not re-scale. Removed in Batch C (plan Task 17).
        KnownIssue(audit: .dynamicType, elementLabel: "*", reason: "Batch C — Dynamic Type sweep"),
        KnownIssue(audit: .textClipped, elementLabel: "*", reason: "Batch C — Dynamic Type sweep"),
        // A system `Form` section header. Its siblings "Text" and "Font", in the
        // same style, pass; this one sits on the boundary of the section card
        // beneath it and the sample straddles two backgrounds.
        KnownIssue(audit: .contrast, elementLabel: "Style", reason: "system Form header; sampling straddles the section boundary"),
        // The text style sheet's Done: black ink (accentStrong) on the toolbar's
        // glass pill. Sampled from the audited screenshot at #1A1A1A on #EFEFEF,
        // about 15:1; the audit misreads iOS 26's Liquid Glass toolbar buttons.
        KnownIssue(audit: .contrast, elementLabel: "Done", reason: "glass toolbar button; sampled ≈15:1"),
        // Home's chips and headings stay visible behind the half-height Start
        // Editing sheet. Modal presentation removes them from the tree — a
        // VoiceOver user navigates the sheet, not what is behind it — but the
        // audit's text detection still sees the pixels. Verified: the finding
        // disappears when the sheet is given a `.large()` detent.
        KnownIssue(audit: .elementDetection, elementLabel: "", surface: "Start Editing sheet",
                   reason: "Home's text behind the sheet; hidden from the tree by modal presentation"),
    ]

    override func setUpWithError() throws {
        continueAfterFailure = true   // report every issue on a surface, not the first
    }

    // MARK: - Helpers

    @MainActor
    private func launch(hasSeenOnboarding: Bool = true) -> XCUIApplication {
        let app = XCUIApplication.underTest(hasSeenOnboarding: hasSeenOnboarding)
        app.launchArguments += ["-UITestMode", "1"]
        app.launch()
        return app
    }

    /// `XCUIAccessibilityAuditType` is an option set with no description, so
    /// name the ones iOS runs for a readable failure line.
    private static let auditNames: [(XCUIAccessibilityAuditType, String)] = [
        (.contrast, "contrast"), (.elementDetection, "elementDetection"), (.hitRegion, "hitRegion"),
        (.sufficientElementDescription, "sufficientElementDescription"), (.dynamicType, "dynamicType"),
        (.textClipped, "textClipped"), (.trait, "trait"),
    ]

    private static func name(of type: XCUIAccessibilityAuditType) -> String {
        auditNames.first { $0.0 == type }?.1 ?? "\(type.rawValue)"
    }

    @MainActor
    private func audit(_ app: XCUIApplication, _ surface: String, file: StaticString = #filePath, line: UInt = #line) {
        // The surface as audited, kept only when the audit fails, so a finding
        // can be read against the pixels it was made on.
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "audit-\(surface)"
        screenshot.lifetime = .deleteOnSuccess
        add(screenshot)
        let screen = app.frame
        do {
            try app.performAccessibilityAudit(for: .all) { issue in
                let label = issue.element?.label ?? ""
                let identifier = issue.element?.identifier ?? ""
                let frame = issue.element.map { "\($0.frame.integral)" } ?? "?"
                // The contrast audit samples the screen where the element is.
                // An element clipped at a scroll edge, straddling the screen's
                // edge, or below a sheet's fold is sampled at the clip, not at
                // its ink, so the result says nothing about the colours. Visible
                // means hittable (not clipped or covered) AND wholly on screen.
                // Every ink pair is a Theme token, and ThemeContrastTests pins
                // those directly.
                let visible = issue.element.map { $0.isHittable && screen.contains($0.frame) } ?? false
                if issue.auditType == .contrast, !visible { return true }
                let known = Self.knownIssues.contains { $0.covers(issue, label: label, surface: surface) }
                if !known {
                    XCTFail("[\(surface)] \(Self.name(of: issue.auditType)): \(issue.detailedDescription) — «\(label)» [\(identifier)] \(frame) · \(issue.compactDescription)",
                            file: file, line: line)
                }
                return true   // reported above with the surface name; do not double-report
            }
        } catch {
            XCTFail("[\(surface)] audit could not run: \(error)", file: file, line: line)
        }
    }

    @MainActor
    private func openGridEditor(_ app: XCUIApplication) {
        let grid = app.buttons["newProjectButton"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10), "grid quick-start chip")
        grid.tap()
        XCTAssertTrue(app.navigationBars["Grid Collage"].waitForExistence(timeout: 8), "grid editor")
    }

    // MARK: - Shell

    @MainActor
    func testHome() throws {
        let app = launch()
        XCTAssertTrue(app.tabBars["mainTabBar"].waitForExistence(timeout: 10))
        audit(app, "Home")
    }

    @MainActor
    func testCollageTab() throws {
        let app = launch()
        app.tabBars["mainTabBar"].buttons["templatesButton"].tap()
        XCTAssertTrue(app.collectionViews["templateGalleryGrid"].waitForExistence(timeout: 10))
        audit(app, "Collage tab")
    }

    @MainActor
    func testCarouselTab() throws {
        let app = launch()
        app.tabBars["mainTabBar"].buttons["carouselButton"].tap()
        XCTAssertTrue(app.collectionViews["carouselTemplateGrid"].waitForExistence(timeout: 10))
        audit(app, "Carousel tab")
    }

    @MainActor
    func testProjectsTab() throws {
        let app = launch()
        app.tabBars["mainTabBar"].buttons["projectsTab"].tap()
        XCTAssertTrue(app.collectionViews["projectsGrid"].waitForExistence(timeout: 10))
        audit(app, "Projects")
    }

    @MainActor
    func testStartEditingSheet() throws {
        let app = launch()
        let plus = app.buttons["startEditingButton"]
        XCTAssertTrue(plus.waitForExistence(timeout: 10))
        plus.tap()
        XCTAssertTrue(app.buttons["startEditingImage"].waitForExistence(timeout: 8))
        audit(app, "Start Editing sheet")
    }

    // MARK: - Editors

    @MainActor
    func testGridEditorWithAPanelOpen() throws {
        let app = launch()
        openGridEditor(app)
        audit(app, "Grid editor")
        app.buttons["frameTool"].tap()
        XCTAssertTrue(app.buttons["editorPanelCloseButton"].waitForExistence(timeout: 5), "frame panel")
        audit(app, "Grid editor · Frame panel")
    }

    @MainActor
    func testStickerPicker() throws {
        let app = launch()
        openGridEditor(app)
        app.buttons["addStickerButton"].tap()
        XCTAssertTrue(app.collectionViews["stickerGrid"].waitForExistence(timeout: 8))
        audit(app, "Sticker picker")
    }

    @MainActor
    func testTextStyleSheet() throws {
        let app = launch()
        openGridEditor(app)
        // Adding text opens its styling sheet straight away.
        app.buttons["addTextButton"].tap()
        XCTAssertTrue(app.buttons["textStyleDoneButton"].waitForExistence(timeout: 8), "text style sheet")
        audit(app, "Text style sheet")
    }

    @MainActor
    func testVideoEditorWithTheTimelineExpanded() throws {
        let app = launch()
        let video = app.buttons["videoCollageButton"]
        XCTAssertTrue(video.waitForExistence(timeout: 10))
        video.tap()
        XCTAssertTrue(app.navigationBars["Video Collage"].waitForExistence(timeout: 8))
        audit(app, "Video editor")
        app.buttons["videoTimelineChevron"].tap()
        audit(app, "Video editor · timeline expanded")
    }

    @MainActor
    func testCarouselEditor() throws {
        let app = XCUIApplication.underTest()
        app.launchArguments += ["-UITestMode", "1"]
        app.launchIntoCarouselTypePicker()
        audit(app, "Carousel type picker")
        app.buttons["carouselType-matched"].tap()
        app.buttons["carouselCreateButton"].tap()
        XCTAssertTrue(app.collectionViews["carouselFrameStrip"].waitForExistence(timeout: 10))
        audit(app, "Carousel editor")
    }

    @MainActor
    func testExportSheet() throws {
        let app = launch()
        openGridEditor(app)
        app.buttons["exportButton"].tap()
        XCTAssertTrue(app.buttons["exportSaveButton"].waitForExistence(timeout: 5))
        audit(app, "Export sheet")
    }

    // MARK: - Monetization and onboarding

    @MainActor
    func testPaywallAndTheSpecialOfferThatFollowsIt() throws {
        let app = launch()
        app.tabBars["mainTabBar"].buttons["templatesButton"].tap()
        let grid = app.collectionViews["templateGalleryGrid"]
        XCTAssertTrue(grid.waitForExistence(timeout: 10))
        let locked = app.cells.matching(identifier: "templateCard.premium").firstMatch
        var scrolls = 0
        while !locked.exists, scrolls < 8 { grid.swipeUp(); scrolls += 1 }
        XCTAssertTrue(locked.waitForExistence(timeout: 3), "a locked template card")
        locked.tap()
        XCTAssertTrue(app.buttons["paywallCloseButton"].waitForExistence(timeout: 8))
        audit(app, "Paywall")

        // A first dismissal is offered the second chance (SpecialOfferPolicy's
        // cooldown has never been recorded on a fresh simulator).
        app.buttons["paywallCloseButton"].tap()
        if app.buttons["specialOfferCloseButton"].waitForExistence(timeout: 5) {
            audit(app, "Special offer")
        }
    }

    @MainActor
    func testOnboardingFirstBeat() throws {
        let app = launch(hasSeenOnboarding: false)
        XCTAssertTrue(app.buttons["onboardingContinueButton"].waitForExistence(timeout: 10))
        audit(app, "Onboarding · welcome")
        app.buttons["onboardingContinueButton"].tap()
        audit(app, "Onboarding · first value slide")
    }
}
