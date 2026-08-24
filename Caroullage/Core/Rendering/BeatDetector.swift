//
//  BeatDetector.swift
//  Caroullage
//
//  Step 04 slice 6c — the onset/beat detector behind auto-beat-sync (the plan's
//  "analyze audio onsets via AVAudioEngine + onset detection").
//
//  Energy-based onset detection: frame the mono signal into hops, take the
//  half-wave-rectified frame-to-frame energy rise (the "novelty" curve), and
//  peak-pick it against a local adaptive threshold with a refractory gap so a
//  single hit can't fire twice. The algorithm is a pure function over PCM samples,
//  so it's unit-tested against a synthesized click track; `detectOnsets(in:)` only
//  decodes + downmixes an asset and hands the samples to it.
//

import AVFoundation
import Foundation

public struct BeatDetector {

    public struct Parameters: Sendable {
        /// Analysis frame stride in samples (~23 ms at 22.05 kHz).
        public var hopSize: Int = 512
        /// Minimum gap between reported onsets — collapses double-triggers.
        public var minInterOnset: Double = 0.15
        /// How far above the local novelty mean+σ a peak must sit.
        public var thresholdMultiplier: Double = 1.5
        /// Half-width (frames) of the adaptive-threshold window.
        public var windowFrames: Int = 8
        /// A peak must also clear this fraction of the loudest novelty — rejects
        /// silence-level noise (e.g. AAC quantization between beats).
        public var relativeFloor: Double = 0.1
        /// Sample rate the asset is decoded to before analysis.
        public var analysisSampleRate: Double = 22_050

        public init() {}
    }

    public init() {}

    // MARK: - Pure core

    /// Onset times (seconds) in a mono PCM signal sampled at `sampleRate`.
    public static func onsets(
        fromMonoSamples samples: [Float],
        sampleRate: Double,
        parameters: Parameters = Parameters()
    ) -> [Double] {
        let hop = max(1, parameters.hopSize)
        guard sampleRate > 0, samples.count >= hop * 2 else { return [] }
        let frameCount = samples.count / hop

        // Short-time energy per frame.
        var energy = [Double](repeating: 0, count: frameCount)
        for k in 0 ..< frameCount {
            let base = k * hop
            var sum = 0.0
            for i in base ..< base + hop {
                let v = Double(samples[i])
                sum += v * v
            }
            energy[k] = sum
        }

        // Novelty = half-wave-rectified energy rise.
        var novelty = [Double](repeating: 0, count: frameCount)
        for k in 1 ..< frameCount {
            novelty[k] = max(0, energy[k] - energy[k - 1])
        }

        let globalMax = novelty.max() ?? 0
        guard globalMax > 0 else { return [] }
        let floor = globalMax * parameters.relativeFloor
        let w = max(1, parameters.windowFrames)

        var onsets: [Double] = []
        var lastOnsetTime = -Double.greatestFiniteMagnitude

        for k in 1 ..< max(1, frameCount - 1) {
            let value = novelty[k]
            // Local maximum, above the absolute floor.
            guard value > floor, value >= novelty[k - 1], value >= novelty[k + 1] else { continue }
            // Above the local adaptive threshold (mean + mult·σ).
            let lo = max(0, k - w), hi = min(frameCount - 1, k + w)
            let window = novelty[lo ... hi]
            let mean = window.reduce(0, +) / Double(window.count)
            let variance = window.reduce(0) { $0 + ($1 - mean) * ($1 - mean) } / Double(window.count)
            guard value > mean + parameters.thresholdMultiplier * variance.squareRoot() else { continue }
            // Refractory gap.
            let time = Double(k * hop) / sampleRate
            guard time - lastOnsetTime >= parameters.minInterOnset else { continue }
            onsets.append(time)
            lastOnsetTime = time
        }
        return onsets
    }

    // MARK: - From an audio asset

    /// Decodes `asset`'s audio to mono float PCM and returns its onset times.
    /// Requires a real audio track; verified headlessly against a generated file.
    public func detectOnsets(
        in asset: AVAsset,
        parameters: Parameters = Parameters()
    ) async throws -> [Double] {
        guard let track = try await asset.loadTracks(withMediaType: .audio).first else { return [] }
        let reader = try AVAssetReader(asset: asset)
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 32,
            AVLinearPCMIsFloatKey: true,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: parameters.analysisSampleRate])
        guard reader.canAdd(output) else { return [] }
        reader.add(output)
        guard reader.startReading() else { throw reader.error ?? BeatError.readFailed }

        var samples: [Float] = []
        while let sampleBuffer = output.copyNextSampleBuffer() {
            guard let block = CMSampleBufferGetDataBuffer(sampleBuffer) else { continue }
            let length = CMBlockBufferGetDataLength(block)
            var chunk = [Float](repeating: 0, count: length / MemoryLayout<Float>.size)
            CMBlockBufferCopyDataBytes(block, atOffset: 0, dataLength: length, destination: &chunk)
            samples.append(contentsOf: chunk)
        }
        if reader.status == .failed { throw reader.error ?? BeatError.readFailed }

        return Self.onsets(fromMonoSamples: samples,
                           sampleRate: parameters.analysisSampleRate, parameters: parameters)
    }

    public enum BeatError: Error { case readFailed }
}
