//
//  CarouselThumbnailCache.swift
//  Caroullage
//
//  Step 06 device QA — long-pressing a frame zoomed in with a visible stutter.
//
//  The animation was never the problem. Frame thumbnails were rendered inside
//  `cellForItemAt`, synchronously, through the same Core Graphics compositor the
//  export uses — and the editor threw the entire cache away on every view-model
//  change. So a context-menu zoom ran against N full-canvas renders on the main
//  thread, and a one-frame edit re-rendered all ten.
//
//  Keying on a frame's CONTENT rather than on "something changed" is what fixes
//  it. A frame is invalidated when its own state changes and at no other time —
//  in particular a reorder, which changes `CarouselFrame.index` and no pixels,
//  costs nothing.
//

import UIKit

final class CarouselThumbnailCache {

    private struct Entry {
        let state: GridEditorState
        let image: UIImage
    }

    private var entries: [UUID: Entry] = [:]

    /// The cached thumbnail, or `nil` if there is none or it no longer depicts the
    /// frame as it stands.
    func image(for frame: CarouselFrame) -> UIImage? {
        guard let entry = entries[frame.id], entry.state == frame.state else { return nil }
        return entry.image
    }

    func store(_ image: UIImage, for frame: CarouselFrame) {
        entries[frame.id] = Entry(state: frame.state, image: image)
    }

    /// Drops entries for frames that no longer exist, so a long editing session
    /// does not accumulate bitmaps for deleted frames.
    func prune(keeping frames: [CarouselFrame]) {
        let live = Set(frames.map(\.id))
        entries = entries.filter { live.contains($0.key) }
    }

    func removeAll() {
        entries.removeAll()
    }
}
