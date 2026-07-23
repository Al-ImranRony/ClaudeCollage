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
//  Step 04 slice 4 extends it: per-cell intro transitions (crossfade / slide /
//  zoom) via layer-instruction opacity/transform ramps; `photoCell(...)` turns a
//  photo into a looping still-video track so photos and videos mix; and `export`
//  writes the composed video via the DIRECT AVAssetReaderVideoCompositionOutput →
//  AVAssetWriter path (no AVAssetExportSession), drawing text/sticker overlays onto
//  each frame at write-time (the AVVideoCompositionCoreAnimationTool path crashes
//  the reader — see VideoCompositionBundle.overlayImage).
//

import AVFoundation
import CoreGraphics
import CoreMedia
import CoreVideo
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
    /// Optional intro animation for this cell (applied via layer-instruction ramps).
    public var transition: CellTransition?

    public init(
        asset: AVAsset,
        frame: CGRect,
        trim: VideoTrim = VideoTrim(),
        isLooping: Bool = false,
        isMuted: Bool = false,
        volume: Double = 1,
        transition: CellTransition? = nil
    ) {
        self.asset = asset
        self.frame = frame
        self.trim = trim
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.volume = volume
        self.transition = transition
    }
}

/// The optional background-music track to mix under the cells. The resolved
/// `AVAsset` is the builder input; the persisted counterpart is
/// `BackgroundMusicState` (the editor resolves `musicID` → asset).
public struct BackgroundMusic {
    public let asset: AVAsset
    /// In/out selection within the source audio (unset end ⇒ whole track).
    public var trim: VideoTrim
    /// Music level, 0…1.
    public var volume: Double

    public init(asset: AVAsset, trim: VideoTrim = VideoTrim(), volume: Double = 1) {
        self.asset = asset
        self.trim = trim
        self.volume = volume
    }
}

/// The assembled composition + its video composition (per-cell layout/transform)
/// + audio mix (per-cell mute/volume), ready to preview or export.
///
/// `overlayImage` is the pre-rendered text+sticker layer (full-canvas, transparent).
/// It is NOT part of the video composition — baking it there via
/// `AVVideoCompositionCoreAnimationTool` crashes `AVAssetReaderVideoCompositionOutput`
/// (no Core Animation render server in that pipeline / the simulator). Instead
/// `export(bundle:…)` draws it onto each composited frame at write-time, and the
/// live preview overlays it as a CALayer above the player. Either way, preview ==
/// export because the same `VideoOverlayRenderer` image is used.
public struct VideoCompositionBundle {
    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let duration: CMTime
    public let renderSize: CGSize
    public let overlayImage: CGImage?
}

extension VideoComposer {

    private static let compositionTimescale: CMTimeScale = 600

    /// Assembles `cells` into a collage composition sized to `canvasSize`.
    ///
    /// `textOverlays` / `stickerOverlays` are baked over the whole video via an
    /// `AVVideoCompositionCoreAnimationTool`, reusing the image-export renderers so
    /// the video matches the photo export. Any per-cell `transition` animates via
    /// layer-instruction opacity/transform ramps at the cell's start.
    public func buildComposition(
        cells: [VideoCompositionCell],
        canvasSize: CGSize,
        music: BackgroundMusic? = nil,
        textOverlays: [TextOverlay] = [],
        stickerOverlays: [StickerOverlay] = [],
        textFontScale: CGFloat = 1,
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
            applyPlacement(transform, transition: item.cell.transition,
                           cellFrame: item.cell.frame, clipDuration: item.range.duration,
                           timescale: ts, to: layer)
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

        // 4) Optional background music: its own composition audio track, trimmed
        //    to the composition duration (no loop v1 — a shorter track just ends),
        //    levelled through the audio mix at its own gain.
        if let music,
           let musicSource = try await music.asset.loadTracks(withMediaType: .audio).first {
            let musicAssetDuration = try await music.asset.load(.duration).seconds
            let musicTrim = music.trim.clamped(toAssetDuration: musicAssetDuration)
            let insertSeconds = min(musicTrim.duration, totalSeconds)
            if insertSeconds > 0,
               let musicTrack = composition.addMutableTrack(withMediaType: .audio,
                                                            preferredTrackID: kCMPersistentTrackID_Invalid) {
                let musicRange = CMTimeRange(
                    start: CMTime(seconds: musicTrim.start, preferredTimescale: ts),
                    duration: CMTime(seconds: insertSeconds, preferredTimescale: ts))
                try? musicTrack.insertTimeRange(musicRange, of: musicSource, at: .zero)
                let params = AVMutableAudioMixInputParameters(track: musicTrack)
                params.setVolume(Float(min(1, max(0, music.volume))), at: .zero)
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

        let overlayImage = VideoOverlayRenderer.overlayImage(
            textOverlays: textOverlays, stickerOverlays: stickerOverlays,
            canvasPx: canvasSize, textFontScale: textFontScale)

        return VideoCompositionBundle(composition: composition, videoComposition: videoComposition,
                                      audioMix: audioMix, duration: total, renderSize: canvasSize,
                                      overlayImage: overlayImage)
    }

    /// Turns a photo cell into a video track: renders `image` as a short still clip
    /// (at its natural size) and wraps it as a muted, looping `VideoCompositionCell`.
    /// `buildComposition` then aspect-fits it into `frame` and loops it to fill the
    /// composition duration — so photos and videos mix on equal footing. The still
    /// clip is written to `url`; the caller owns its lifetime (delete after export).
    public func photoCell(
        image: CGImage,
        frame: CGRect,
        holdSeconds: Double = 0.5,
        to url: URL
    ) async throws -> VideoCompositionCell {
        try await renderSlideshow(frames: [image],
                                  size: CGSize(width: image.width, height: image.height),
                                  secondsPerFrame: holdSeconds, to: url)
        return VideoCompositionCell(asset: AVURLAsset(url: url), frame: frame,
                                    isLooping: true, isMuted: true)
    }

    /// Exports the assembled bundle to a video file via the DIRECT
    /// `AVAssetReaderVideoCompositionOutput` → `AVAssetWriter` path (no
    /// `AVAssetExportSession`, preserving fidelity per slice 1). Text/sticker
    /// overlays (`bundle.overlayImage`) are drawn onto each composited frame at
    /// write-time. When the composition carries audio (cell audio and/or background
    /// music), the `bundle.audioMix` is decoded through an `AVAssetReaderAudioMixOutput`
    /// and muxed into the file via an AAC audio input. Runs the blocking pull loop on
    /// a private queue, bridged to async.
    public func export(
        bundle: VideoCompositionBundle,
        codec: ExportSettings.VideoCodec = .h264,
        container: ExportPreset.VideoContainer = .mp4,
        to url: URL,
        progress: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        let tracks = try await bundle.composition.loadTracks(withMediaType: .video)
        guard !tracks.isEmpty else { throw ComposerError.noFrames }
        let audioTracks = try await bundle.composition.loadTracks(withMediaType: .audio)

        let width = Int(bundle.renderSize.width.rounded())
        let height = Int(bundle.renderSize.height.rounded())

        let reader = try AVAssetReader(asset: bundle.composition)
        let readerOutput = AVAssetReaderVideoCompositionOutput(
            videoTracks: tracks,
            videoSettings: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA])
        readerOutput.videoComposition = bundle.videoComposition
        guard reader.canAdd(readerOutput) else { throw ComposerError.writerSetupFailed }
        reader.add(readerOutput)

        let fileType: AVFileType = container == .mov ? .mov : .mp4
        let writer = try AVAssetWriter(url: url, fileType: fileType)
        let codecType: AVVideoCodecType = codec == .hevc ? .hevc : .h264
        let writerInput = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codecType, AVVideoWidthKey: width, AVVideoHeightKey: height])
        writerInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: writerInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height])
        guard writer.canAdd(writerInput) else { throw ComposerError.writerSetupFailed }
        writer.add(writerInput)

        // Audio: decode the composition's audio tracks through the mix (stereo LPCM)
        // and re-encode to AAC. Skipped entirely when there is no source audio, so a
        // silent slideshow stays video-only exactly as before.
        var audioOutput: AVAssetReaderAudioMixOutput?
        var audioInput: AVAssetWriterInput?
        if !audioTracks.isEmpty {
            let output = AVAssetReaderAudioMixOutput(
                audioTracks: audioTracks, audioSettings: Self.pcmReaderSettings)
            output.audioMix = bundle.audioMix
            if reader.canAdd(output) {
                reader.add(output)
                let input = AVAssetWriterInput(mediaType: .audio, outputSettings: Self.aacWriterSettings)
                input.expectsMediaDataInRealTime = false
                if writer.canAdd(input) {
                    writer.add(input)
                    audioOutput = output
                    audioInput = input
                }
            }
        }

        let context = ExportContext(reader: reader, output: readerOutput, writer: writer,
                                    input: writerInput, adaptor: adaptor,
                                    audioOutput: audioOutput, audioInput: audioInput,
                                    overlay: bundle.overlayImage,
                                    width: width, height: height, duration: bundle.duration.seconds)
        let exportQueue = DispatchQueue(label: "com.devron.claudecollage.videoexport")
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            exportQueue.async {
                do { try Self.runExport(context, progress: progress); cont.resume() }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    /// Stereo 16-bit LPCM — the audio-mix output must decode to PCM for the mix
    /// gains to apply; an explicit stereo layout keeps mono sources well-defined.
    private static var pcmReaderSettings: [String: Any] {
        var stereo = AudioChannelLayout()
        stereo.mChannelLayoutTag = kAudioChannelLayoutTag_Stereo
        let layout = Data(bytes: &stereo, count: MemoryLayout<AudioChannelLayout>.size)
        return [
            AVFormatIDKey: kAudioFormatLinearPCM,
            AVLinearPCMBitDepthKey: 16,
            AVLinearPCMIsFloatKey: false,
            AVLinearPCMIsBigEndianKey: false,
            AVLinearPCMIsNonInterleaved: false,
            AVSampleRateKey: 44_100,
            AVNumberOfChannelsKey: 2,
            AVChannelLayoutKey: layout
        ]
    }

    private static var aacWriterSettings: [String: Any] {
        [
            AVFormatIDKey: kAudioFormatMPEG4AAC,
            AVNumberOfChannelsKey: 2,
            AVSampleRateKey: 44_100,
            AVEncoderBitRateKey: 128_000
        ]
    }

    /// Carries the non-Sendable reader/writer objects into the export queue. Safe:
    /// they're used only on that queue, never concurrently.
    private struct ExportContext: @unchecked Sendable {
        let reader: AVAssetReader
        let output: AVAssetReaderVideoCompositionOutput
        let writer: AVAssetWriter
        let input: AVAssetWriterInput
        let adaptor: AVAssetWriterInputPixelBufferAdaptor
        let audioOutput: AVAssetReaderAudioMixOutput?
        let audioInput: AVAssetWriterInput?
        let overlay: CGImage?
        let width: Int
        let height: Int
        let duration: Double
    }

    /// Drains the reader's video (and optional audio) outputs into the writer,
    /// interleaving both on this single queue: each input is fed whenever it is
    /// ready, so neither backs up. Video frames get the overlay drawn in place
    /// before append; audio samples pass through re-encoded by the AAC input.
    private static func runExport(_ ctx: ExportContext, progress: (@Sendable (Float) -> Void)?) throws {
        guard ctx.reader.startReading() else { throw ctx.reader.error ?? ComposerError.writeFailed }
        guard ctx.writer.startWriting() else { throw ctx.writer.error ?? ComposerError.writerSetupFailed }
        ctx.writer.startSession(atSourceTime: .zero)

        var videoDone = false
        var audioDone = (ctx.audioInput == nil)

        while !videoDone || !audioDone {
            var progressed = false

            if !videoDone, ctx.input.isReadyForMoreMediaData {
                if let sample = ctx.output.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if let buffer = CMSampleBufferGetImageBuffer(sample) {
                        if let overlay = ctx.overlay {
                            drawOverlay(overlay, into: buffer, width: ctx.width, height: ctx.height)
                        }
                        if !ctx.adaptor.append(buffer, withPresentationTime: pts) {
                            ctx.reader.cancelReading(); ctx.writer.cancelWriting()
                            throw ctx.writer.error ?? ComposerError.writeFailed
                        }
                        if ctx.duration > 0 { progress?(Float(min(1, pts.seconds / ctx.duration))) }
                    }
                    progressed = true
                } else {
                    ctx.input.markAsFinished()
                    videoDone = true
                }
            }

            if !audioDone, let audioInput = ctx.audioInput, let audioOutput = ctx.audioOutput,
               audioInput.isReadyForMoreMediaData {
                if let sample = audioOutput.copyNextSampleBuffer() {
                    if !audioInput.append(sample) {
                        ctx.reader.cancelReading(); ctx.writer.cancelWriting()
                        throw ctx.writer.error ?? ComposerError.writeFailed
                    }
                    progressed = true
                } else {
                    audioInput.markAsFinished()
                    audioDone = true
                }
            }

            if !progressed { Thread.sleep(forTimeInterval: 0.003) }
        }

        if ctx.reader.status == .failed { throw ctx.reader.error ?? ComposerError.writeFailed }
        let sema = DispatchSemaphore(value: 0)
        ctx.writer.finishWriting { sema.signal() }
        sema.wait()
        guard ctx.writer.status == .completed else { throw ctx.writer.error ?? ComposerError.writeFailed }
    }

    /// Composites the overlay image onto a BGRA composited frame in place. The
    /// reader's frame buffer and the `UIGraphicsImageRenderer` overlay image share
    /// the same top-down raster orientation, so `draw` needs no CTM flip (verified
    /// by the overlay pixel-readback test — a flip put the overlay upside down).
    private static func drawOverlay(_ overlay: CGImage, into buffer: CVPixelBuffer, width: Int, height: Int) {
        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue) else { return }
        ctx.draw(overlay, in: CGRect(x: 0, y: 0, width: width, height: height))
    }

    // MARK: - Helpers

    private struct ResolvedVideoCell {
        let cell: VideoCompositionCell
        let videoTrack: AVAssetTrack
        let audioTrack: AVAssetTrack?
        let naturalSize: CGSize
        let range: CMTimeRange
    }

    /// Sets a cell's resting placement transform, plus — if it has an intro
    /// transition — the opacity/transform ramp that animates it in over the
    /// transition window (clamped to the clip's length) starting at t=0.
    private func applyPlacement(
        _ transform: CGAffineTransform,
        transition: CellTransition?,
        cellFrame: CGRect,
        clipDuration: CMTime,
        timescale: CMTimeScale,
        to layer: AVMutableVideoCompositionLayerInstruction
    ) {
        guard let transition, transition.duration > 0 else {
            layer.setTransform(transform, at: .zero)
            return
        }
        let window = CMTimeRange(
            start: .zero,
            duration: CMTimeMinimum(CMTime(seconds: transition.duration, preferredTimescale: timescale),
                                    clipDuration))
        let startTransform = VideoCompositionMath.transitionStartTransform(
            style: transition.style, base: transform, cell: cellFrame)
        if startTransform != transform {
            layer.setTransformRamp(fromStart: startTransform, toEnd: transform, timeRange: window)
        } else {
            layer.setTransform(transform, at: .zero)
        }
        let startOpacity = VideoCompositionMath.transitionStartOpacity(transition.style)
        if startOpacity != 1 {
            layer.setOpacityRamp(fromStartOpacity: startOpacity, toEndOpacity: 1, timeRange: window)
        }
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
