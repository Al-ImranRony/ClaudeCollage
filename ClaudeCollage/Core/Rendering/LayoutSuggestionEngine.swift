//
//  LayoutSuggestionEngine.swift
//  ClaudeCollage
//
//  Step 05 batch A — "AI auto-layout": pick the grids that treat these photos best.
//
//  Pure. Vision supplies where the faces and salient regions are; this decides
//  what that means for a layout, and none of it needs a device to test.
//
//  The idea: a collage cell rarely matches its photo's aspect ratio, so the photo
//  is centre-cropped to fill. That crop can slice a face in half. Scoring a
//  template = predicting that crop for each photo and measuring how much of what
//  matters survives.
//

import CoreGraphics
import Foundation

/// What Vision found in one photo. Rects are normalized with a TOP-LEFT origin —
/// converted from Vision's bottom-left space by `AIService` so this engine and
/// the rest of the app share one convention.
public struct PhotoFeatures: Equatable, Sendable {

    /// Pixel aspect ratio (width / height).
    public let aspectRatio: CGFloat
    public let faces: [CGRect]
    public let salientRegions: [CGRect]

    public init(aspectRatio: CGFloat, faces: [CGRect] = [], salientRegions: [CGRect] = []) {
        self.aspectRatio = max(aspectRatio, 0.0001)
        self.faces = faces
        self.salientRegions = salientRegions
    }

    /// What the engine tries to preserve. Faces dominate: a cropped face reads as
    /// a mistake in a way a cropped background never does.
    var regionsOfInterest: [(rect: CGRect, weight: CGFloat)] {
        faces.map { ($0, Self.faceWeight) }
            + salientRegions.map { ($0, Self.saliencyWeight) }
    }

    private static let faceWeight: CGFloat = 1.0
    private static let saliencyWeight: CGFloat = 0.35
}

/// A scored template, best first.
public struct LayoutSuggestion: Equatable, Sendable {
    public let template: GridTemplate
    public let score: CGFloat
}

public struct LayoutSuggestionEngine: Sendable {

    private let engine = CollageLayoutEngine()

    public init() {}

    /// Best templates for these photos, highest score first.
    ///
    /// - Parameter limit: how many to return (the brief asks for five).
    ///
    /// Templates with fewer cells than photos are still allowed — dropping a
    /// photo is a legitimate suggestion — but they are penalised in proportion to
    /// what they leave out, and a template with more cells than photos is
    /// penalised for the empty slots it would open.
    public func suggestions(
        for photos: [PhotoFeatures],
        canvasSize: CGSize = CGSize(width: 1080, height: 1080),
        limit: Int = 5
    ) -> [LayoutSuggestion] {
        guard !photos.isEmpty, limit > 0 else { return [] }

        let scored = GridTemplate.allCases.map { template in
            LayoutSuggestion(
                template: template,
                score: score(template, for: photos, canvasSize: canvasSize)
            )
        }
        // Sorted by raw value on ties so the order is deterministic — otherwise
        // the suggestion row reshuffles between identical runs.
        return scored
            .sorted { ($0.score, $1.template.rawValue) > ($1.score, $0.template.rawValue) }
            .prefix(limit)
            .map { $0 }
    }

    /// 0…1. How well this template treats this set of photos.
    public func score(
        _ template: GridTemplate,
        for photos: [PhotoFeatures],
        canvasSize: CGSize = CGSize(width: 1080, height: 1080)
    ) -> CGFloat {
        guard !photos.isEmpty else { return 0 }

        let cells = engine.layout(for: template, canvasSize: canvasSize)
        guard !cells.isEmpty else { return 0 }

        let used = min(cells.count, photos.count)
        var total: CGFloat = 0
        for index in 0 ..< used {
            total += preservation(of: photos[index], in: cells[index].frame)
        }
        let preservationScore = total / CGFloat(used)

        // Penalties, so "fits the photos I actually have" beats "crops nothing
        // because it only shows one of them".
        let dropped = max(0, photos.count - cells.count)
        let empty = max(0, cells.count - photos.count)
        let droppedPenalty = CGFloat(dropped) / CGFloat(photos.count) * 0.6
        let emptyPenalty = CGFloat(empty) / CGFloat(cells.count) * 0.4

        return max(0, preservationScore - droppedPenalty - emptyPenalty)
    }

    // MARK: - Private

    /// Fraction of this photo's weighted regions of interest that survive being
    /// centre-cropped to fill `cellFrame`.
    ///
    /// A photo with nothing detected scores on aspect similarity alone: with no
    /// faces to protect, the best cell is simply the one that crops least.
    private func preservation(of photo: PhotoFeatures, in cellFrame: CGRect) -> CGFloat {
        guard cellFrame.width > 0, cellFrame.height > 0 else { return 0 }
        let cellAspect = cellFrame.width / cellFrame.height
        let visible = Self.centreCropRect(photoAspect: photo.aspectRatio, cellAspect: cellAspect)

        let regions = photo.regionsOfInterest
        guard !regions.isEmpty else {
            return Self.aspectAffinity(photo.aspectRatio, cellAspect)
        }

        var kept: CGFloat = 0
        var weight: CGFloat = 0
        for region in regions {
            let overlap = region.rect.intersection(visible)
            let area = region.rect.width * region.rect.height
            guard area > 0 else { continue }
            let survived = overlap.isNull ? 0 : (overlap.width * overlap.height) / area
            kept += survived * region.weight
            weight += region.weight
        }
        guard weight > 0 else { return Self.aspectAffinity(photo.aspectRatio, cellAspect) }

        // Blended with aspect affinity so that among templates which preserve the
        // faces equally, the one that crops least still wins.
        let preserved = kept / weight
        return preserved * 0.8 + Self.aspectAffinity(photo.aspectRatio, cellAspect) * 0.2
    }

    /// The normalized part of a photo still visible after centre-cropping it to
    /// fill a cell of `cellAspect`. Top-left origin.
    static func centreCropRect(photoAspect: CGFloat, cellAspect: CGFloat) -> CGRect {
        if photoAspect > cellAspect {
            // Photo is wider: sides are cropped away.
            let width = cellAspect / photoAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        } else {
            // Photo is taller: top and bottom go.
            let height = photoAspect / cellAspect
            return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
        }
    }

    /// 1 when the shapes match, falling off as they diverge.
    static func aspectAffinity(_ photoAspect: CGFloat, _ cellAspect: CGFloat) -> CGFloat {
        guard photoAspect > 0, cellAspect > 0 else { return 0 }
        let ratio = photoAspect / cellAspect
        return min(ratio, 1 / ratio)
    }
}
