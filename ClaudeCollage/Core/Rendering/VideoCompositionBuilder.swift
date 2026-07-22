//
//  VideoCompositionBuilder.swift
//  ClaudeCollage
//
//  Step 04 slice 3 — assembles video cells into an AVMutableComposition + video
//  composition + audio mix. Each cell becomes its own composition track so cells
//  can be transformed and composited independently; the clip is trimmed to the
//  cell's in/out and, when looping, repeated to fill the composition duration.
//  A layer instruction places each clip in its canvas rect (aspect-fit affine
//  transform); an AVMutableAudioMix carries per-cell mute/volume.
//
//  Export of the assembled composition still flows through the slice-1 DIRECT
//  AVAssetReader→AVAssetWriter path — no AVAssetExportSession.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

/// One video cell to assemble into the collage composition.
public struct VideoCompositionCell {
    public let asset: AVAsset
    /// Absolute canvas-pixel frame this cell occupies (top-left origin).
    public let frame: CGRect
    public var trim: VideoTrim
    public var isLooping: Bool
    public var isMuted: Bool
    public var volume: Double

    public init(
        asset: AVAsset,
        frame: CGRect,
        trim: VideoTrim = VideoTrim(),
        isLooping: Bool = false,
        isMuted: Bool = false,
        volume: Double = 1
    ) {
        self.asset = asset
        self.frame = frame
        self.trim = trim
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.volume = volume
    }
}

/// The assembled composition + its video composition (per-cell layout/transform)
/// + audio mix (per-cell mute/volume), ready to preview or export.
public struct VideoCompositionBundle {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let duration: CMTime
    public let renderSize: CGSize
}

extension VideoComposer {

    private static let compositionTimescale: CMTimeScale = 600

    /// Assembles `cells` into a collage composition sized to `canvasSize`.
    public func buildComposition(
        cells: [VideoCompositionCell],
        canvasSize: CGSize,
        fps: Int32 = 30
    ) async throws -> VideoCompositionBundle {
        let composition = AVMutableComposition()
        let ts = Self.compositionTimescale

        // 1) Resolve each cell's source tracks + trimmed range up front.
        var resolved: [ResolvedVideoCell] = []
        for cell in cells {
            guard let videoTrack = try await cell.asset.loadTracks(withMediaType: .video).first else { continue }
            let assetDuration = try await cell.asset.load(.duration).seconds
            let trimmed = cell.trim.clamped(toAssetDuration: assetDuration)
            guard trimmed.duration > 0 else { continue }
            let naturalSize = try await videoTrack.load(.naturalSize)
            let audioTrack = try await cell.asset.loadTracks(withMediaType: .audio).first
            let range = CMTimeRange(
                start: CMTime(seconds: trimmed.start, preferredTimescale: ts),
                duration: CMTime(seconds: trimmed.duration, preferredTimescale: ts))
            resolved.append(ResolvedVideoCell(cell: cell, videoTrack: videoTrack, audioTrack: audioTrack,
                                              naturalSize: naturalSize, range: range))
        }

        // 2) Composition duration = the longest trimmed cell.
        let totalSeconds = VideoCompositionMath.compositionDuration(cellDurations: resolved.map { $0.range.duration.seconds })
        let total = CMTime(seconds: totalSeconds, preferredTimescale: ts)

        // 3) One video track + layer instruction (+ audio) per cell.
        var layerInstructions: [AVMutableVideoCompositionLayerInstruction] = []
        var audioParameters: [AVMutableAudioMixInputParameters] = []

        for item in resolved {
            guard let videoComp = composition.addMutableTrack(withMediaType: .video,
                                                              preferredTrackID: kCMPersistentTrackID_Invalid)
            else { continue }
            let fillTo = item.cell.isLooping ? total : item.range.duration
            try insertLooping(range: item.range, of: item.videoTrack, into: videoComp, fillTo: fillTo)

            let layer = AVMutableVideoCompositionLayerInstruction(assetTrack: videoComp)
            // AVFoundation's video-composition layer transforms use the same
            // top-left origin as the canvas (verified by the placement tests), so
            // the cell's canvas frame is used directly — no y-flip.
            let transform = VideoCompositionMath.aspectFitTransform(
                source: item.naturalSize, in: item.cell.frame)
            layer.setTransform(transform, at: .zero)
            layerInstructions.append(layer)

            if let audioTrack = item.audioTrack,
               let audioComp = composition.addMutableTrack(withMediaType: .audio,
                                                           preferredTrackID: kCMPersistentTrackID_Invalid) {
                try? insertLooping(range: item.range, of: audioTrack, into: audioComp, fillTo: fillTo)
                let params = AVMutableAudioMixInputParameters(track: audioComp)
                params.setVolume(VideoCompositionMath.effectiveVolume(isMuted: item.cell.isMuted,
                                                                      volume: item.cell.volume), at: .zero)
                audioParameters.append(params)
            }
        }

        let instruction = AVMutableVideoCompositionInstruction()
        instruction.timeRange = CMTimeRange(start: .zero, duration: total)
        instruction.layerInstructions = layerInstructions

        let videoComposition = AVMutableVideoComposition()
        videoComposition.renderSize = canvasSize
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        videoComposition.instructions = [instruction]

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters

        return VideoCompositionBundle(composition: composition, videoComposition: videoComposition,
                                      audioMix: audioMix, duration: total, renderSize: canvasSize)
    }

    // MARK: - Helpers

    private struct ResolvedVideoCell {
        let cell: VideoCompositionCell
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let naturalSize: CGSize
        let range: CMTimeRange
    }

    /// Inserts `range` of `source` into `dest`, repeating it until `fillTo` is
    /// reached (looping cells). A single insert when `fillTo <= range.duration`.
    private func insertLooping(range: CMTimeRange, of source: AVAssetTrack,
                               into dest: AVMutableCompositionTrack, fillTo: CMTime) throws {
        var cursor = CMTime.zero
        while cursor < fillTo {
            let remaining = fillTo - cursor
            let thisDuration = CMTimeMinimum(range.duration, remaining)
            guard thisDuration > .zero else { break }
            try dest.insertTimeRange(CMTimeRange(start: range.start, duration: thisDuration),
                                     of: source, at: cursor)
            cursor = cursor + thisDuration
        }
    }
}
