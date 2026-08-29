//
//  CarouselThumbnailCacheTests.swift
//  CaroullageTests
//
//  Step 06 device QA — long-pressing a frame zoomed in with a visible stutter.
//
//  The animation was not the problem. `cellForItemAt` rendered each frame's
//  thumbnail synchronously through the full Core Graphics compositor, and every
//  view-model change threw the whole cache away — so a context-menu animation was
//  competing with N full-canvas renders on the main thread.
//
//  This cache is the fix's memory: it is keyed by a frame's CONTENT, so an edit to
//  one frame costs one re-render and a reorder costs none. The invalidation rules
//  are what these tests pin; the off-main rendering is wired in the editor.
//

import UIKit
import XCTest
@testable import Caroullage

final class CarouselThumbnailCacheTests: XCTestCase {

    private let red = UIImage(systemName: "circle.fill")!
    private let blue = UIImage(systemName: "square.fill")!

    private func frame(_ index: Int, background: CollageBackground = .white) -> CarouselFrame {
        var state = GridEditorState()
        state.background = background
        return CarouselFrame(index: index, state: state)
    }

    func testAStoredThumbnailComesBack() {
        let cache = CarouselThumbnailCache()
        let f = frame(0)
        cache.store(red, for: f)
        XCTAssertIdentical(cache.image(for: f), red)
    }

    func testAnUnknownFrameMisses() {
        let cache = CarouselThumbnailCache()
        XCTAssertNil(cache.image(for: frame(0)))
    }

    func testEditingAFrameInvalidatesItsOwnThumbnail() {
        let cache = CarouselThumbnailCache()
        var f = frame(0)
        cache.store(red, for: f)

        f.state.background = .black
        XCTAssertNil(cache.image(for: f),
                     "The stored bitmap no longer shows what the frame contains")
    }

    func testEditingOneFrameLeavesTheOthersCached() {
        // This is the actual defect: `reloadFrames()` cleared everything, so a
        // one-frame edit re-rendered all ten.
        let cache = CarouselThumbnailCache()
        var edited = frame(0)
        let untouched = frame(1, background: .black)
        cache.store(red, for: edited)
        cache.store(blue, for: untouched)

        edited.state.background = .solid(hex: "#123456")
        _ = cache.image(for: edited)

        XCTAssertIdentical(cache.image(for: untouched), blue,
                           "A neighbouring frame's thumbnail must survive an unrelated edit")
    }

    func testReorderingDoesNotInvalidateAnything() {
        // `CarouselFrame` is Equatable including its `index`, so keying on the whole
        // value would make Move Left re-render every frame in the carousel for a
        // change that alters no pixels.
        let cache = CarouselThumbnailCache()
        var f = frame(0)
        cache.store(red, for: f)

        f.index = 4
        XCTAssertIdentical(cache.image(for: f), red,
                           "A frame's position does not change what it looks like")
    }

    func testRemoveAllClearsTheCache() {
        let cache = CarouselThumbnailCache()
        let f = frame(0)
        cache.store(red, for: f)
        cache.removeAll()
        XCTAssertNil(cache.image(for: f))
    }

    func testTwoFramesWithIdenticalContentKeepSeparateEntries() {
        // Same state, different identity: a duplicated frame must not alias.
        let cache = CarouselThumbnailCache()
        let a = frame(0)
        let b = frame(0)
        cache.store(red, for: a)
        XCTAssertNil(cache.image(for: b))
    }
}
