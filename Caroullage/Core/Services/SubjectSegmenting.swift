//
//  SubjectSegmenting.swift
//  Caroullage
//
//  Step 05 batch A — the seam between the AI features and Vision.
//
//  Every Vision request the AI features need is an ML request, and ML requests
//  DO NOT RUN IN THE SIMULATOR: `VNGenerateForegroundInstanceMaskRequest` fails
//  with "Could not create inference context", saliency and face detection with
//  "Failed to create espresso context". There is no neural-engine backend there.
//
//  So Vision sits behind this protocol and nothing else in the app touches it.
//  Mask compositing, layout scoring and all error handling live on the far side
//  as pure functions, which makes them testable headlessly against a stub — and
//  keeps the same pure-engine / thin-adapter split the rendering and video code
//  already use.
//
//  Rects are NORMALIZED (0…1) in Vision's coordinate space: origin bottom-left.
//  `AIService` converts to the top-left space the rest of the app uses, once, so
//  callers never have to think about it.
//

import CoreGraphics
import CoreVideo
import Foundation
import VideoToolbox
import Vision

/// Source of on-device image understanding.
public protocol SubjectSegmenting: Sendable {

    /// Grayscale mask of the most prominent foreground subject: white where the
    /// subject is, black elsewhere. `nil` when the image has no clear subject.
    func foregroundMask(for image: CGImage) async throws -> CGImage?

    /// Detected faces, normalized, Vision coordinates (origin bottom-left).
    func faceRects(in image: CGImage) async throws -> [CGRect]

    /// Attention-salient regions, normalized, Vision coordinates.
    func salientRects(in image: CGImage) async throws -> [CGRect]
}

/// What went wrong, in terms a user-facing message can be written from.
public enum SegmentationError: Error, Equatable {
    /// The request ran but found nothing to lift.
    case noSubjectFound
    /// Vision itself could not run — most often the simulator's missing
    /// inference context, but also thermal or memory pressure on device.
    case visionUnavailable(String)
}

// MARK: - Vision-backed implementation

/// The real thing. Device-only in practice — see the file header.
public struct VisionSubjectSegmenter: SubjectSegmenting {

    public init() {}

    public func foregroundMask(for image: CGImage) async throws -> CGImage? {
        let request = VNGenerateForegroundInstanceMaskRequest()
        try perform([request], on: image)

        guard let result = request.results?.first, !result.allInstances.isEmpty else {
            return nil
        }
        // Every instance at once: a "subject" the user lifted by tapping a photo
        // is usually one thing, but a person holding an object is two instances
        // and lifting only one of them looks broken.
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        let buffer = try result.generateScaledMaskForImage(
            forInstances: result.allInstances, from: handler)
        return Self.makeCGImage(from: buffer)
    }

    public func faceRects(in image: CGImage) async throws -> [CGRect] {
        let request = VNDetectFaceRectanglesRequest()
        try perform([request], on: image)
        return (request.results ?? []).map(\.boundingBox)
    }

    public func salientRects(in image: CGImage) async throws -> [CGRect] {
        let request = VNGenerateAttentionBasedSaliencyImageRequest()
        try perform([request], on: image)
        guard let observation = request.results?.first else { return [] }
        return (observation.salientObjects ?? []).map(\.boundingBox)
    }

    // MARK: - Private

    private func perform(_ requests: [VNRequest], on image: CGImage) throws {
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        do {
            try handler.perform(requests)
        } catch {
            // Surfaced as a distinct case so callers can say "not available on
            // this device" rather than "your photo failed".
            throw SegmentationError.visionUnavailable(error.localizedDescription)
        }
    }

    private static func makeCGImage(from buffer: CVPixelBuffer) -> CGImage? {
        var image: CGImage?
        VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &image)
        return image
    }
}
