//
//  TextAnimationTests.swift
//  CaroullageTests
//
//  The reserved tier-3 animation field (spec §4.1). NOTHING reads it yet — it
//  exists so that shipping fade / slide / pop / typewriter later is a change to
//  the two render call sites rather than a document migration.
//
//  That makes the decode tests the whole point of this file: the field is only
//  worth adding early if a project written by a build that USES it still opens
//  here, and if this build re-saving that project does not destroy the choice.
//  Hence `animationRaw` is stored as the raw string (the `alignmentRaw`
//  precedent on this same type) rather than as a decoded enum.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class TextAnimationTests: XCTestCase {

    // MARK: - Default

    func testAnOverlayHasNoAnimationByDefault() {
        XCTAssertEqual(TextOverlay(text: "hi").animation, TextAnimation.none)
    }

    func testTheDefaultIsUnchangedByTheOtherInitParameters() {
        let overlay = TextOverlay(text: "hi", fontSize: 12, style: TextStyle(kind: .glow))
        XCTAssertEqual(overlay.animation, TextAnimation.none)
    }

    // MARK: - Round trips

    func testEveryAnimationRoundTrips() throws {
        for animation in TextAnimation.allCases {
            var overlay = TextOverlay(text: "hi")
            overlay.animation = animation

            let data = try JSONEncoder().encode(overlay)
            let decoded = try JSONDecoder().decode(TextOverlay.self, from: data)

            XCTAssertEqual(decoded.animation, animation, "\(animation) must survive a round trip")
        }
    }

    func testTheAccessorAndItsRawStorageAgree() {
        var overlay = TextOverlay(text: "hi")
        overlay.animation = .typewriter
        XCTAssertEqual(overlay.animationRaw, "typewriter")
    }

    // MARK: - Backward compatibility (a project saved before this field existed)

    func testAnOverlaySavedBeforeAnimationExistedDecodesToNone() throws {
        // The exact shape of a pre-change snapshot: no `animationRaw` key at all.
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","fontName":"SFProDisplay-Semibold",
         "fontSize":64,"colorHex":"#000000","alignmentRaw":"center","letterSpacing":0,
         "lineHeight":1.1,"opacity":1,"isBold":false,"isItalic":false,"isUnderlined":false,
         "frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertEqual(overlay.animation, TextAnimation.none)
        XCTAssertEqual(overlay.text, "hi", "the rest of the overlay must still decode")
    }

    // MARK: - Forward compatibility (a project saved by a build that ships tier 3)

    func testAnUnknownAnimationFallsBackToNoneRatherThanThrowing() throws {
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","colorHex":"#000000",
         "animationRaw":"kenBurns","frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)

        let overlay = try JSONDecoder().decode(TextOverlay.self, from: json)

        XCTAssertEqual(overlay.animation, TextAnimation.none,
                       "an animation this build has never heard of must not throw away the project")
    }

    func testAnUnknownAnimationSurvivesBeingReSavedByThisBuild() throws {
        // The reason the raw string is stored rather than a decoded enum. Opening
        // a newer project here shows no animation, but re-saving must not silently
        // downgrade the user's choice to `.none` for the build that understands it.
        let json = Data(##"""
        {"id":"3F2504E0-4F89-11D3-9A0C-0305E82C3301","text":"hi","colorHex":"#000000",
         "animationRaw":"kenBurns","frameX":0,"frameY":0,"frameWidth":1,"frameHeight":1}
        """##.utf8)

        let reSaved = try JSONEncoder().encode(try JSONDecoder().decode(TextOverlay.self, from: json))
        let decoded = try JSONDecoder().decode(TextOverlay.self, from: reSaved)

        XCTAssertEqual(decoded.animationRaw, "kenBurns")
        XCTAssertEqual(decoded.animation, TextAnimation.none)
    }

    // MARK: - Reserved really does mean nothing reads it

    func testAnimationDoesNotAffectRendering() {
        // Guards the "reserved" half of the spec: until tier 3 has its own spec,
        // setting this must change nothing about how the overlay draws. If this
        // starts failing, someone has wired a render path ahead of that spec.
        var plain = TextOverlay(text: "Hello", fontSize: 64)
        plain.style = TextStyle(kind: .stroke, colorHex: "#FF0000", width: 4)
        var animated = plain
        animated.animation = .typewriter

        XCTAssertEqual(
            TextRendering.attributedString(for: animated, fontScale: 1),
            TextRendering.attributedString(for: plain, fontScale: 1))
    }

    func testAnimationDoesNotAffectVisibilityWindows() {
        var overlay = TextOverlay(text: "hi")
        overlay.startTime = 2
        overlay.endTime = 5
        var animated = overlay
        animated.animation = .fade

        for time in [0.0, 1.99, 2, 4.99, 5, 9_999] {
            XCTAssertEqual(animated.isVisible(at: time), overlay.isVisible(at: time),
                           "animation must not shift the in/out window at \(time)")
        }
    }

    // MARK: - Equatable

    func testOverlaysDifferingOnlyInAnimationAreNotEqual() {
        let plain = TextOverlay(id: UUID(), text: "hi")
        var animated = plain
        animated.animation = .pop
        XCTAssertNotEqual(plain, animated)
    }
}
