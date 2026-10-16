//
//  TextAnimationMathTests.swift
//  CaroullageTests
//
//  The one function both renderers call for a caption's animated state. Its
//  timing rules are the contract the live canvas and the export share, so they
//  are pinned here rather than through either renderer.
//

import XCTest
import CoreGraphics
@testable import Caroullage

final class TextAnimationMathTests: XCTestCase {

    private func overlay(
        _ text: String = "One two three", animation: TextAnimation,
        start: Double? = nil, end: Double? = nil
    ) -> TextOverlay {
        TextOverlay(text: text, animation: animation, startTime: start, endTime: end,
                    frame: CGRect(x: 0.1, y: 0.1, width: 0.8, height: 0.2))
    }

    // MARK: - None

    func testNoAnimationIsAlwaysAtRest() {
        let caption = overlay(animation: .none, start: 1, end: 3)
        for time in [0.0, 1, 1.01, 2.99, 5] {
            XCTAssertTrue(TextAnimationMath.frame(for: caption, at: time).isRest)
        }
    }

    // MARK: - Fade

    func testFadeRisesFromTransparentAtItsInPoint() {
        let caption = overlay(animation: .fade, start: 2, end: 6)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 2).opacity, 0, accuracy: 1e-6)
        let mid = TextAnimationMath.frame(for: caption, at: 2.15).opacity
        XCTAssertGreaterThan(mid, 0.2)
        XCTAssertLessThan(mid, 1)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 3).opacity, 1, accuracy: 1e-6)
    }

    func testFadeFallsToTransparentAtItsOutPoint() {
        let caption = overlay(animation: .fade, start: 0, end: 4)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 3.5).opacity, 1, accuracy: 1e-6)
        XCTAssertLessThan(TextAnimationMath.frame(for: caption, at: 3.9).opacity, 0.5)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 4).opacity, 0, accuracy: 1e-6)
    }

    func testAnUnboundedCaptionNeverFadesOut() {
        let caption = overlay(animation: .fade)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 9_999).opacity, 1, accuracy: 1e-6)
    }

    func testANilInPointAnimatesFromTheStartOfTheVideo() {
        let caption = overlay(animation: .fade)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 0).opacity, 0, accuracy: 1e-6)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 1).opacity, 1, accuracy: 1e-6)
    }

    func testBeforeTheInPointNothingIsDrawn() {
        let caption = overlay(animation: .pop, start: 3, end: 5)
        XCTAssertTrue(TextAnimationMath.frame(for: caption, at: 1).isInvisible)
    }

    // MARK: - Rise and pop

    func testRiseStartsBelowAndSettlesInPlace() {
        let caption = overlay(animation: .slide, start: 0, end: 5)
        XCTAssertGreaterThan(TextAnimationMath.frame(for: caption, at: 0).offset.dy, 0.3)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 1).offset.dy, 0, accuracy: 1e-6)
    }

    func testPopOvershootsThenSettlesAtFullSize() {
        let caption = overlay(animation: .pop, start: 0, end: 5)
        XCTAssertLessThan(TextAnimationMath.frame(for: caption, at: 0).scale, 0.7)
        let peak = (0 ... 40).map { TextAnimationMath.frame(for: caption, at: Double($0) / 100).scale }.max() ?? 0
        XCTAssertGreaterThan(peak, 1.03, "a pop overshoots before it settles")
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 1).scale, 1, accuracy: 1e-6)
    }

    // MARK: - Word reveals

    func testWordsRevealInOrder() {
        let caption = overlay("How to make these", animation: .words, start: 0, end: 4)
        let early = TextAnimationMath.frame(for: caption, at: 0.1)
        XCTAssertEqual(early.rangeAlphas.count, 4)
        XCTAssertGreaterThan(early.rangeAlphas[0].alpha, 0.9, "the first word is up")
        XCTAssertEqual(early.rangeAlphas[3].alpha, 0, accuracy: 1e-6, "the last is still hidden")

        let late = TextAnimationMath.frame(for: caption, at: 3)
        XCTAssertTrue(late.rangeAlphas.allSatisfy { $0.alpha >= 0.999 }, "all words up by then")
    }

    func testPunctuationRevealsWithItsWord() {
        let units = TextAnimationMath.wordUnits(in: "collage videos.")
        XCTAssertEqual(units.map(\.length), [7, 7], "“videos.” is one unit, full stop included")
    }

    func testLineBreaksSeparateWords() {
        let units = TextAnimationMath.wordUnits(in: "WORD\nBY\nWORD")
        XCTAssertEqual(units.count, 3)
    }

    func testWordFadeIsSofterThanWordSnap() {
        let snap = overlay("a b", animation: .words, start: 0, end: 4)
        let soft = overlay("a b", animation: .wordFade, start: 0, end: 4)
        // A moment after the first word begins: the snap is already up, the fade is not.
        let t = 0.07
        XCTAssertGreaterThan(TextAnimationMath.frame(for: snap, at: t).rangeAlphas[0].alpha, 0.9)
        XCTAssertLessThan(TextAnimationMath.frame(for: soft, at: t).rangeAlphas[0].alpha, 0.9)
    }

    func testAShortCaptionRevealsFasterThanALongOne() {
        let short = overlay("a b c d", animation: .words, start: 0, end: 1.2)
        let long = overlay("a b c d", animation: .words, start: 0, end: 6)
        XCTAssertLessThan(TextAnimationMath.entranceDuration(for: short),
                          TextAnimationMath.entranceDuration(for: long))
    }

    func testTypewriterRevealsCharactersAndSkipsSpaces() {
        let caption = overlay("ab c", animation: .typewriter, start: 0, end: 4)
        let frame = TextAnimationMath.frame(for: caption, at: 0)
        XCTAssertEqual(frame.rangeAlphas.count, 3, "a, b and c — the space has nothing to reveal")
    }

    func testAnEmojiRevealsWhole() {
        let units = TextAnimationMath.characterUnits(in: "hi👋🏽")
        XCTAssertEqual(units.count, 3)
        XCTAssertEqual(units.last?.length, ("👋🏽" as NSString).length)
    }

    // MARK: - Caching

    func testQuantizationMergesImperceptibleDifferences() {
        let a = TextAnimationFrame(opacity: 0.5)
        let b = TextAnimationFrame(opacity: 0.5 + 1e-5)
        XCTAssertNotEqual(a, b)
        XCTAssertEqual(a.quantized, b.quantized)
    }

    func testARestingCaptionHasAStableFrame() {
        let caption = overlay(animation: .wordFade, start: 0, end: 8)
        XCTAssertEqual(TextAnimationMath.frame(for: caption, at: 4).quantized,
                       TextAnimationMath.frame(for: caption, at: 5).quantized,
                       "once revealed, consecutive frames share one export render")
    }
}
