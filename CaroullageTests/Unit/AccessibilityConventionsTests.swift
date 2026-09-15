//
//  AccessibilityConventionsTests.swift
//  CaroullageTests
//
//  Step 06 phase 6.5. Three conventions, checked on every design-system
//  component by walking its laid-out view tree:
//
//   1. Anything a user can press has a label. A `UIControl` or a `.button`
//      element with no `accessibilityLabel` and no title is announced by
//      VoiceOver as "button" — or, worse, by the SF Symbol's internal name.
//   2. Its hit region is at least 44×44pt. Probed with `point(inside:)` at the
//      corners of a 44pt square centred on the view, so a control that grew its
//      hit area without growing its bounds (`HitTargetButton`) passes and a
//      control that merely *looks* big enough does not.
//   3. Every label re-scales live with Dynamic Type. `Theme.Typography` fonts
//      are scaled through `UIFontMetrics` at creation, but a `UILabel` only
//      follows a later change of the setting when
//      `adjustsFontForContentSizeCategory` is on — without it the text is the
//      right size at launch and stale after the user changes it.
//
//  Stock `UISlider`/`UISwitch`/`UISegmentedControl` are exempt from (2): they
//  carry Apple's own sizing, and Xcode's audit does not flag them either.
//
//  The XCUI audit (AccessibilityAuditUITests) covers the same ground on the
//  running app, broadly and slowly; this is the fast, precise half.
//

import UIKit
import XCTest
@testable import Caroullage

@MainActor
final class AccessibilityConventionsTests: XCTestCase {

    private static let phoneWidth: CGFloat = 402

    /// Labels that deliberately do not re-scale, by accessibility identifier —
    /// each one a recorded decision rather than a missing assert.
    private static let fixedSizeLabelIdentifiers: Set<String> = [
        // The text-style preset card's "Aa": the collage's own text, rendered
        // through TextRendering at canvas scale. A preview of a style, not UI.
        "textStylePreviewSample",
    ]

    // MARK: - The roster

    func testTheEditorToolRailFollowsTheConventions() {
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: Self.phoneWidth, height: EditorToolRail.contentHeight)
        rail.setBaseTools([
            EditorTool(id: "layout", title: "Layout", systemImage: "square.grid.2x2",
                       accessibilityIdentifier: "layoutTool"),
            EditorTool(id: "frame", title: "Frame", systemImage: "square.dashed",
                       accessibilityIdentifier: "frameTool"),
        ])
        rail.setContext(EditorRailContext(
            chipTitle: "Photo", chipSystemImage: "photo",
            tools: [EditorTool(id: "replace", title: "Replace", systemImage: "arrow.2.squarepath",
                               accessibilityIdentifier: "replacePhotoTool")]))
        assertAccessibilityConventions(in: rail)
    }

    func testTheEditorPanelFollowsTheConventions() {
        let panel = EditorPanel()
        panel.frame = CGRect(x: 0, y: 0, width: Self.phoneWidth, height: 160)
        let slider = UISlider()
        slider.accessibilityLabel = "Border"
        panel.show(
            EditorPanelRow.stack([
                EditorPanelRow.make(title: "Border", systemImage: "square.dashed", trailing: slider),
            ]),
            title: "Frame", animated: false)
        assertAccessibilityConventions(in: panel)
    }

    func testTheFilterMenuChipFollowsTheConventions() {
        let chip = FilterMenuChip(symbolName: "arrow.up.arrow.down", identifier: "sortChip",
                                  accessibilityLabel: "Sort")
        chip.setValue("Recent")
        chip.frame = CGRect(x: 0, y: 0, width: 120, height: 36)
        assertAccessibilityConventions(in: chip)
    }

    func testTheQuickStartTileFollowsTheConventions() {
        let tile = QuickStartTile(title: "Grid", subtitle: "Photo collage", symbol: "square.grid.2x2",
                                  identifier: "newProjectButton", action: {})
        tile.frame = CGRect(x: 0, y: 0, width: 180, height: 96)
        assertAccessibilityConventions(in: tile)
    }

    func testTheTextStylePresetRowFollowsTheConventions() {
        let row = TextStylePresetRow(selected: nil, onSelect: { _ in })
        row.frame = CGRect(x: 0, y: 0, width: Self.phoneWidth, height: 96)
        assertAccessibilityConventions(in: row)
    }

    func testTheVideoTimelineFollowsTheConventions() {
        let timeline = VideoTimeline()
        timeline.frame = CGRect(x: 0, y: 0, width: Self.phoneWidth, height: VideoTimeline.expandedHeight)
        timeline.setModel(VideoTimelineModel(
            duration: 12,
            clips: [VideoTimelineModel.Clip(index: 0, start: 0, duration: 6, isFilled: true),
                    VideoTimelineModel.Clip(index: 1, start: 6, duration: 6, isFilled: false)],
            textPills: [VideoTimelineModel.TextPill(id: UUID(), label: "Hello", start: 1, end: 4)],
            musicTitle: "Track", selectedClipIndex: 0, selectedTextID: nil, isPlaying: false))
        timeline.setState(.expanded, animated: false)
        assertAccessibilityConventions(in: timeline)
    }

    func testTheThemeButtonFollowsTheConventions() {
        let button = ThemeButton(style: .primary, title: "Continue", action: UIAction { _ in })
        button.frame = CGRect(x: 0, y: 0, width: 200, height: 52)
        assertAccessibilityConventions(in: button)
    }

    // MARK: - The walker

    /// Walks `root`'s laid-out subtree and asserts the conventions on every
    /// visible interactive view. Failure messages name the view's class and
    /// identifier so the offending control can be found without a debugger.
    func assertAccessibilityConventions(in root: UIView, file: StaticString = #filePath, line: UInt = #line) {
        root.layoutIfNeeded()
        var pending: [UIView] = [root]
        while let view = pending.popLast() {
            // A button's internals are the system's: a configured UIButton
            // re-runs its titleTextAttributesTransformer on a trait change, so
            // its inner label re-scales without the flag. The button itself is
            // what gets checked.
            if !(view is UIButton) { pending.append(contentsOf: view.subviews) }
            guard !view.isHidden, view.alpha > 0.01 else { continue }

            if let label = view as? UILabel, !(label.text ?? "").isEmpty,
               !Self.fixedSizeLabelIdentifiers.contains(label.accessibilityIdentifier ?? "") {
                XCTAssertTrue(label.adjustsFontForContentSizeCategory,
                              "\(type(of: view)) [\(label.accessibilityIdentifier ?? label.text!)] does not re-scale with Dynamic Type",
                              file: file, line: line)
            }

            let isInteractive = view is UIControl || view.accessibilityTraits.contains(.button)
            guard isInteractive else { continue }
            let name = "\(type(of: view)) [\(view.accessibilityIdentifier ?? "no identifier")]"

            let label = view.accessibilityLabel
                ?? (view as? UIButton)?.currentTitle
                ?? (view as? UIButton)?.configuration?.title
                ?? ""
            XCTAssertFalse(label.trimmingCharacters(in: .whitespaces).isEmpty,
                           "\(name) has no accessibility label", file: file, line: line)

            guard !(view is UISlider || view is UISwitch || view is UISegmentedControl) else { continue }
            let half = Theme.Layout.minimumHitTarget / 2 - 0.5
            let centre = CGPoint(x: view.bounds.midX, y: view.bounds.midY)
            let corners = [CGPoint(x: centre.x - half, y: centre.y - half),
                           CGPoint(x: centre.x + half, y: centre.y + half)]
            for corner in corners {
                XCTAssertTrue(view.point(inside: corner, with: nil),
                              "\(name) hit region is under 44×44 (bounds \(view.bounds.size))",
                              file: file, line: line)
            }
        }
    }
}

// MARK: - Large content viewer (phase 6.5)

/// Compact controls that cannot grow with the text offer the large content
/// viewer instead: press-and-hold shows the control's name and glyph full-screen.
@MainActor
final class LargeContentViewerTests: XCTestCase {

    func testEveryRailToolOffersItsTitleAndGlyphToTheLargeContentViewer() {
        let rail = EditorToolRail()
        rail.frame = CGRect(x: 0, y: 0, width: 402, height: EditorToolRail.contentHeight)
        rail.setBaseTools([
            EditorTool(id: "frame", title: "Frame", systemImage: "square.dashed",
                       accessibilityIdentifier: "frameTool"),
        ])
        rail.layoutIfNeeded()
        XCTAssertTrue(rail.interactions.contains { $0 is UILargeContentViewerInteraction },
                      "the rail hosts the interaction")
        let button = rail.toolButton(for: "frame")!
        XCTAssertTrue(button.showsLargeContentViewer)
        XCTAssertEqual(button.largeContentTitle, "Frame")
        XCTAssertNotNil(button.largeContentImage)
    }

    func testTheTimelinesHeaderControlsFollowTheirSpokenLabels() {
        let timeline = VideoTimeline()
        timeline.frame = CGRect(x: 0, y: 0, width: 402, height: VideoTimeline.expandedHeight)
        timeline.setModel(VideoTimelineModel(duration: 4, isPlaying: true))
        timeline.layoutIfNeeded()
        let play = timeline.headerControlsForTesting.playback
        let chevron = timeline.headerControlsForTesting.chevron
        XCTAssertTrue(play.showsLargeContentViewer && chevron.showsLargeContentViewer)
        XCTAssertEqual(play.largeContentTitle, "Pause")
        XCTAssertEqual(chevron.largeContentTitle, "Expand timeline")
        XCTAssertNotNil(play.largeContentImage)
    }
}
