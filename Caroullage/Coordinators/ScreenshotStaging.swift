//
//  ScreenshotStaging.swift
//  Caroullage
//
//  Step 06 phase 6.7. When the app is launched with `-ScreenshotMode 1`, the
//  quick-start doors open editors already filled with the bundled, licensed
//  sample photography and video loops (`Resources/SampleContent`, credited in
//  its ATTRIBUTION.md), so App Store screenshots show real collages rather
//  than empty wells. `AppStoreScreenshotUITests` drives it; nothing here runs
//  in a normal launch.
//
//  The photos are the same ones Home's showcase composites, chosen by hand
//  here for the strongest combinations rather than by manifest order.
//

import AVFoundation
import UIKit

@MainActor
enum ScreenshotStaging {

    static var isActive: Bool {
        ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")
    }

    /// Photos in the order they read best across a 4-up, a hexagon and a
    /// carousel: a face first, then variety.
    private static let photoNames = [
        "sample_portrait_01", "sample_travel_02", "sample_food_01", "sample_friends_02",
        "sample_travel_01", "sample_portrait_03", "sample_seasonal_01", "sample_couple_01",
        "sample_family_01", "sample_travel_03", "sample_food_03", "sample_portrait_05",
    ]

    /// The first `count` sample photos, as the editors take them.
    static func samplePhotos(count: Int, offset: Int = 0) -> [CGImage] {
        let names = photoNames.dropFirst(offset).prefix(count)
        return names.compactMap { SampleContentCatalog.shared.image(named: $0)?.cgImage }
    }

    /// Fills every cell of a grid or shape collage.
    static func seed(_ viewModel: GridEditorViewModel, offset: Int = 0) {
        let count = viewModel.state.cells.count
        for (index, image) in samplePhotos(count: count, offset: offset).enumerated() {
            viewModel.setImage(image, forCellAt: index)
        }
    }

    /// Fills the video collage's slots with the bundled loops.
    static func seed(_ viewModel: VideoEditorViewModel) {
        let loops = ["sample_loop_duo", "sample_loop_solo", "sample_loop_quad"]
        for (index, name) in loops.prefix(viewModel.cells.count).enumerated() {
            guard let url = SampleContentCatalog.shared.videoURL(named: name) else { continue }
            viewModel.setVideo(assetID: UUID(), asset: AVURLAsset(url: url), forCellAt: index)
        }
    }

    /// Fills every frame of a carousel, a different run of photos per frame —
    /// the same round trip the editor makes when a frame is opened and closed.
    static func seed(_ viewModel: CarouselEditorViewModel) {
        let selected = viewModel.currentIndex
        for index in viewModel.frames.indices {
            viewModel.selectFrame(index)
            let current = viewModel.currentEditorState()
            let frameVM = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: current.state)
            frameVM.restore(state: current.state, images: current.images)
            seed(frameVM, offset: index * 2)
            viewModel.commitCurrentFrame(state: frameVM.state, images: frameVM.sourceImageSnapshot())
        }
        viewModel.selectFrame(selected)
    }
}
