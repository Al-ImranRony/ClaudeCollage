//
//  AIService.swift
//  Caroullage
//
//  Step 05 batch A — the app's single entry point for on-device intelligence.
//
//  Everything here is on-device: VisionKit / Vision / Core Image / Image
//  Playground. No server, no API key, no per-use cost, and nothing leaves the
//  phone — which is also why the free tier can afford subject lift, magic eraser
//  and auto-layout, and why only Image Playground (Apple Intelligence hardware)
//  sits behind premium.
//
//  The service owns two things worth naming:
//
//  1. The `SubjectSegmenting` seam. Vision cannot run in the simulator, so it is
//     injected and stubbed in tests; see that file's header.
//  2. The coordinate flip. Vision reports normalized rects with a BOTTOM-LEFT
//     origin; the rest of this app is top-left. That conversion happens here,
//     exactly once, so no downstream code has to remember it.
//

import CoreGraphics
import Foundation
import UIKit

@MainActor
public final class AIService: ObservableObject {

    public enum AIError: Error, Equatable {
        case noSubjectFound
        case processingFailed
        case generativeBackgroundsUnavailable
    }

    private let segmenter: SubjectSegmenting
    private let compositor = SubjectCompositor()
    private let suggestionEngine = LayoutSuggestionEngine()

    public init(segmenter: SubjectSegmenting = VisionSubjectSegmenter()) {
        self.segmenter = segmenter
    }

    // MARK: - Subject lifting

    /// Lifts the main subject out of `image`, returning it with a real alpha
    /// channel and trimmed to its own bounds.
    ///
    /// Throws `.noSubjectFound` when there is nothing to lift — a flat landscape,
    /// a texture — which is a normal outcome, not a failure, and the UI should
    /// say so gently rather than presenting it as an error.
    public func liftSubject(from image: CGImage) async throws -> CGImage {
        guard let mask = try await segmenter.foregroundMask(for: image) else {
            throw AIError.noSubjectFound
        }
        guard let masked = compositor.applyMask(mask, to: image) else {
            throw AIError.processingFailed
        }
        guard let cropped = compositor.cropToOpaqueBounds(masked) else {
            // A mask that survived segmentation but is empty once composited.
            throw AIError.noSubjectFound
        }
        return cropped
    }

    /// Photo → sticker: the same lift, named for the workflow it serves so call
    /// sites read honestly.
    public func extractSticker(from image: CGImage) async throws -> CGImage {
        try await liftSubject(from: image)
    }

    // MARK: - Auto-layout

    /// Reads each photo, then scores every grid against what it found.
    ///
    /// Analysis failures degrade rather than throw: a photo Vision could not read
    /// still participates, scored on aspect ratio alone. A suggestion row that
    /// quietly gets less clever is far better than one that disappears.
    public func suggestLayouts(for images: [CGImage], limit: Int = 5) async -> [GridTemplate] {
        guard !images.isEmpty else { return [] }

        var features: [PhotoFeatures] = []
        features.reserveCapacity(images.count)
        for image in images {
            features.append(await self.features(for: image))
        }
        return suggestionEngine.suggestions(for: features, limit: limit).map(\.template)
    }

    /// Vision's findings for one photo, in top-left normalized space.
    func features(for image: CGImage) async -> PhotoFeatures {
        let aspect = CGFloat(image.width) / CGFloat(max(image.height, 1))
        async let faces = try? segmenter.faceRects(in: image)
        async let salient = try? segmenter.salientRects(in: image)

        return PhotoFeatures(
            aspectRatio: aspect,
            faces: (await faces ?? []).map(Self.flippedToTopLeft),
            salientRegions: (await salient ?? []).map(Self.flippedToTopLeft)
        )
    }

    // MARK: - Generative backgrounds (Image Playground)

    /// Whether this device can generate backgrounds at all.
    ///
    /// Requires iOS 18.2+ AND Apple Intelligence hardware, so it is false on the
    /// simulator and on older devices. The UI HIDES the feature when this is
    /// false rather than showing it disabled — offering a paid feature the device
    /// cannot run would be false advertising.
    public var generativeBackgroundsAvailable: Bool {
        ImagePlaygroundAvailability.isAvailable
    }

    // MARK: - Coordinate space

    /// Vision's normalized rects have a bottom-left origin; everything else in
    /// this app is top-left. Flipping y is the whole conversion.
    static func flippedToTopLeft(_ rect: CGRect) -> CGRect {
        CGRect(x: rect.minX, y: 1 - rect.maxY, width: rect.width, height: rect.height)
    }
}

// MARK: - Availability probe

/// Isolated so the availability rule is testable and stated in one place.
enum ImagePlaygroundAvailability {
    static var isAvailable: Bool {
        #if targetEnvironment(simulator)
        // No Apple Intelligence in the simulator, and the framework reports
        // availability inconsistently there — treat it as absent explicitly.
        return false
        #else
        guard #available(iOS 18.2, *) else { return false }
        return ImagePlaygroundAvailabilityBridge.deviceSupportsImagePlayground
        #endif
    }
}

#if !targetEnvironment(simulator)
@available(iOS 18.2, *)
enum ImagePlaygroundAvailabilityBridge {
    /// Resolved at runtime so the app still links and runs on devices whose OS
    /// predates the framework.
    static var deviceSupportsImagePlayground: Bool {
        NSClassFromString("ImagePlaygroundViewController") != nil
    }
}
#endif
