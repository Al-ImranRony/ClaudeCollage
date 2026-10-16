//
//  VideoTimelineMedia.swift
//  Caroullage
//
//  The pictures the timeline draws: frames of each clip, frames of the composed
//  collage, and the shape of the soundtrack. The timeline itself stays a pure
//  renderer — it is handed these values and never touches an `AVAsset` — so
//  producing them is this file's job, driven by the editor.
//
//  Everything is generated off the main actor and cached by MEDIA identity
//  (`videoID` / `musicID`), never by slot: moving a clip, undoing, or trimming
//  costs no regeneration. The composition filmstrip is the one exception — it
//  depicts the whole collage, so each rebuilt composition replaces it.
//

import AVFoundation
import UIKit

// MARK: - Values the timeline draws

/// Frames sampled evenly across a clip's WHOLE source, not its trim window.
///
/// A lane shows only the part its trim covers, picked by source time — so
/// dragging a trim edge reveals or hides real frames under the handle, the way
/// a filmstrip behaves in a pro editor, instead of stretching the few frames
/// the old window had.
public struct VideoTimelineFilmstrip: Equatable {
    public let frames: [UIImage]
    public let sourceDuration: Double

    public init(frames: [UIImage], sourceDuration: Double) {
        self.frames = frames
        self.sourceDuration = sourceDuration
    }

    /// Width over height of the frames, for sizing tiles; square until known.
    public var aspectRatio: CGFloat {
        guard let size = frames.first?.size, size.height > 0 else { return 1 }
        return size.width / size.height
    }

    /// The frame showing `sourceTime`.
    public func frame(at sourceTime: Double) -> UIImage? {
        guard !frames.isEmpty else { return nil }
        guard sourceDuration > 0 else { return frames[0] }
        let fraction = min(max(sourceTime / sourceDuration, 0), 1)
        return frames[min(frames.count - 1, Int(fraction * Double(frames.count)))]
    }

    /// By identity. `UIImage`'s own `==` compares image DATA, and the editor
    /// re-hands the timeline its filmstrips on every refresh — including every
    /// tick of a drag — where the answer is almost always "the same objects".
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.sourceDuration == rhs.sourceDuration && lhs.frames.isIdentical(to: rhs.frames)
    }
}

extension Array where Element == UIImage {
    /// Same images, by object identity rather than by comparing their pixels.
    func isIdentical(to other: [UIImage]) -> Bool {
        count == other.count && zip(self, other).allSatisfy { $0 === $1 }
    }
}

/// The soundtrack's loudness over the stretch of the composition it plays in:
/// peaks in 0…1, spread evenly over `0…duration` composition seconds.
public struct VideoTimelineWaveform: Equatable {
    public let peaks: [Float]
    public let duration: Double

    public init(peaks: [Float], duration: Double) {
        self.peaks = peaks
        self.duration = duration
    }
}

// MARK: - Producing them

/// Owned by the editor: asks for media as the document changes, caches it, and
/// reports when something new is ready to draw. Every request is idempotent, so
/// the editor can simply re-request on each refresh.
@MainActor
final class VideoTimelineMediaLoader {

    /// Something new is ready — redraw the timeline.
    var onUpdate: (() -> Void)?

    private var filmstrips: [UUID: VideoTimelineFilmstrip] = [:]
    /// In flight, or already tried and failed (a clip with no decodable
    /// video) — either way, not to be requested again on the next refresh,
    /// which arrives on every edit.
    private var filmstripsRequested: Set<UUID> = []

    private var musicPeaks: [UUID: (peaks: [Float], sourceDuration: Double)] = [:]
    private var musicRequested: Set<UUID> = []

    private(set) var compositionFrames: [UIImage] = []
    private var compositionTask: Task<Void, Never>?

    /// Frames per clip. Enough that a short trim still changes picture as it
    /// moves; few enough to stay a small, fixed cost per clip.
    static let framesPerClip = 16
    static let compositionFrameCount = 12
    static let peakCount = 400

    // MARK: Clips

    func filmstrip(forVideoID id: UUID) -> VideoTimelineFilmstrip? { filmstrips[id] }

    func requestFilmstrip(videoID: UUID, asset: AVAsset) {
        guard filmstrips[videoID] == nil, !filmstripsRequested.contains(videoID) else { return }
        filmstripsRequested.insert(videoID)
        let box = TimelineAssetBox(asset: asset)
        Task { @MainActor [weak self] in
            let sampled = await Self.sampleFrames(box, count: Self.framesPerClip,
                                                  maximumSize: CGSize(width: 180, height: 180))
            guard let self, !sampled.frames.isEmpty else { return }
            self.filmstrips[videoID] = VideoTimelineFilmstrip(
                frames: sampled.frames, sourceDuration: sampled.duration)
            self.onUpdate?()
        }
    }

    // MARK: The composed collage

    /// Replaces the collapsed strip's filmstrip with frames of `bundle`. A newer
    /// composition cancels an older one still sampling.
    func requestCompositionFrames(for bundle: VideoCompositionBundle) {
        compositionTask?.cancel()
        // Immutable copies: the player is reading the originals.
        guard let composition = bundle.composition.copy() as? AVComposition,
              let videoComposition = bundle.videoComposition.copy() as? AVVideoComposition else { return }
        let box = TimelineAssetBox(asset: composition)
        let composer = TimelineVideoCompositionBox(videoComposition: videoComposition)
        compositionTask = Task { @MainActor [weak self] in
            let sampled = await Self.sampleFrames(box, count: Self.compositionFrameCount,
                                                  maximumSize: CGSize(width: 200, height: 200),
                                                  videoComposition: composer)
            guard let self, !Task.isCancelled, !sampled.frames.isEmpty else { return }
            self.compositionFrames = sampled.frames
            self.onUpdate?()
        }
    }

    func clearCompositionFrames() {
        compositionTask?.cancel()
        guard !compositionFrames.isEmpty else { return }
        compositionFrames = []
        onUpdate?()
    }

    // MARK: Music

    func requestWaveform(musicID: UUID, asset: AVAsset) {
        guard musicPeaks[musicID] == nil, !musicRequested.contains(musicID) else { return }
        musicRequested.insert(musicID)
        let box = TimelineAssetBox(asset: asset)
        Task { @MainActor [weak self] in
            let read = await Self.readPeaks(box, count: Self.peakCount)
            guard let self, !read.peaks.isEmpty else { return }
            self.musicPeaks[musicID] = read
            self.onUpdate?()
        }
    }

    /// The waveform as the composition plays it: the trimmed window, laid from
    /// 0:00 for as long as the music (or the collage, if shorter) lasts —
    /// `VideoComposer` inserts it exactly that way.
    func waveform(musicID: UUID, trim: VideoTrim, compositionDuration: Double) -> VideoTimelineWaveform? {
        guard let read = musicPeaks[musicID] else { return nil }
        return Self.waveform(peaks: read.peaks, sourceDuration: read.sourceDuration,
                             trim: trim, compositionDuration: compositionDuration)
    }

    /// Cuts whole-track `peaks` down to what plays: the trim window, for no
    /// longer than the composition runs.
    nonisolated static func waveform(peaks: [Float], sourceDuration: Double, trim: VideoTrim,
                                     compositionDuration: Double) -> VideoTimelineWaveform? {
        guard !peaks.isEmpty, sourceDuration > 0, compositionDuration > 0 else { return nil }
        let window = trim.clamped(toAssetDuration: sourceDuration)
        let plays = min(window.duration, compositionDuration)
        guard plays > 0 else { return nil }
        let perSecond = Double(peaks.count) / sourceDuration
        let first = min(peaks.count - 1, max(0, Int(window.start * perSecond)))
        let last = min(peaks.count, max(first + 1, Int(((window.start + plays) * perSecond).rounded())))
        return VideoTimelineWaveform(peaks: Array(peaks[first ..< last]), duration: plays)
    }

    // MARK: Off the main actor

    /// `count` frames spread evenly over the asset (each taken from the middle
    /// of its slice). A frame that fails to decode borrows its neighbour's, so
    /// the array always spans the whole duration evenly.
    private nonisolated static func sampleFrames(
        _ box: TimelineAssetBox, count: Int, maximumSize: CGSize,
        videoComposition: TimelineVideoCompositionBox? = nil
    ) async -> (frames: [UIImage], duration: Double) {
        guard let seconds = try? await box.asset.load(.duration).seconds,
              seconds.isFinite, seconds > 0 else { return ([], 0) }
        let generator = AVAssetImageGenerator(asset: box.asset)
        generator.appliesPreferredTrackTransform = true
        generator.maximumSize = maximumSize
        generator.videoComposition = videoComposition?.videoComposition
        // A thumbnail need not be frame-exact; the nearest sync frame is far cheaper.
        let tolerance = CMTime(seconds: seconds / Double(count) / 2, preferredTimescale: 600)
        generator.requestedTimeToleranceBefore = tolerance
        generator.requestedTimeToleranceAfter = tolerance

        var images: [UIImage?] = []
        for index in 0 ..< count {
            if Task.isCancelled { return ([], 0) }
            let time = CMTime(seconds: seconds * (Double(index) + 0.5) / Double(count), preferredTimescale: 600)
            images.append((try? await generator.image(at: time).image).map { UIImage(cgImage: $0) })
        }
        guard let firstGood = images.firstIndex(where: { $0 != nil }) else { return ([], seconds) }
        var last = images[firstGood]
        let filled = images.map { image -> UIImage in
            if let image { last = image }
            return (image ?? last)!
        }
        return (filled, seconds)
    }

    /// Test seam: the waveform reader, for an asset the caller owns.
    nonisolated static func peaksForTesting(of asset: AVAsset, count: Int) async -> [Float] {
        await readPeaks(TimelineAssetBox(asset: asset), count: count).peaks
    }

    /// Peak loudness in `count` equal slices of the asset's first audio track,
    /// normalised so the loudest slice is 1. Read as 16-bit mono at a low
    /// sample rate — the shape of a song survives that easily, and it keeps a
    /// four-minute track to a few hundred milliseconds of work.
    private nonisolated static func readPeaks(
        _ box: TimelineAssetBox, count: Int
    ) async -> (peaks: [Float], sourceDuration: Double) {
        guard let track = try? await box.asset.loadTracks(withMediaType: .audio).first,
              let seconds = try? await box.asset.load(.duration).seconds,
              seconds.isFinite, seconds > 0,
              let reader = try? AVAssetReader(asset: box.asset) else { return ([], 0) }
        let sampleRate = 8_000.0
        let output = AVAssetReaderTrackOutput(track: track, outputSettings: [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVNumberOfChannelsKey: 1,
            AVSampleRateKey: sampleRate,
        ])
        output.alwaysCopiesSampleData = false
        guard reader.canAdd(output) else { return ([], 0) }
        reader.add(output)
        guard reader.startReading() else { return ([], 0) }

        let samplesPerPeak = max(1, Int(seconds * sampleRate) / count)
        var peaks: [Float] = []
        peaks.reserveCapacity(count + 1)
        var current: Int16 = 0
        var inBin = 0
        while let buffer = output.copyNextSampleBuffer() {
            if Task.isCancelled { reader.cancelReading(); return ([], 0) }
            guard let block = CMSampleBufferGetDataBuffer(buffer) else { continue }
            // Whole samples only: a stray odd byte would be copied past the end.
            let count = CMBlockBufferGetDataLength(block) / MemoryLayout<Int16>.size
            guard count > 0 else { continue }
            var samples = [Int16](repeating: 0, count: count)
            let status = samples.withUnsafeMutableBytes { raw -> OSStatus in
                guard let base = raw.baseAddress else { return kCMBlockBufferBadCustomBlockSourceErr }
                return CMBlockBufferCopyDataBytes(block, atOffset: 0,
                                                  dataLength: count * MemoryLayout<Int16>.size,
                                                  destination: base)
            }
            guard status == kCMBlockBufferNoErr else { continue }
            for sample in samples {
                let magnitude = sample == .min ? .max : abs(sample)
                if magnitude > current { current = magnitude }
                inBin += 1
                if inBin == samplesPerPeak {
                    peaks.append(Float(current))
                    current = 0
                    inBin = 0
                }
            }
        }
        // A read that failed partway would spread part of the track across its
        // whole length; better no waveform than a wrong one.
        guard reader.status == .completed else { return ([], 0) }
        if inBin > 0 { peaks.append(Float(current)) }
        guard let loudest = peaks.max(), loudest > 0 else { return (peaks.map { _ in 0 }, seconds) }
        return (peaks.map { $0 / loudest }, seconds)
    }
}

/// Carries the non-Sendable `AVAsset` into the nonisolated samplers; each is
/// only ever read there.
private struct TimelineAssetBox: @unchecked Sendable {
    let asset: AVAsset
}

private struct TimelineVideoCompositionBox: @unchecked Sendable {
    let videoComposition: AVVideoComposition
}
