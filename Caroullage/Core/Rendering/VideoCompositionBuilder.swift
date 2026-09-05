//
//  VideoCompositionBuilder.swift
//  Caroullage
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
///
/// `@unchecked Sendable` so a `@MainActor` editor can hand these to the
/// nonisolated builder: the only non-Sendable member is the `AVAsset`, which is
/// read-only here (never mutated) — the same carry-across-isolation idiom as
/// `VideoAssetLoader.SendableBox` and the exporter's `ExportContext`.
public struct VideoCompositionCell: @unchecked Sendable {

    /// How a clip fits its cell. `.fill` (default) covers the cell edge-to-edge and
    /// crops the overflow — the collage look. `.fit` letterboxes to show the whole
    /// frame.
    public enum ContentMode: Sendable { case fill, fit }

    public let asset: AVAsset
    /// Absolute canvas-pixel frame this cell occupies (top-left origin).
    public let frame: CGRect
    public var trim: VideoTrim
    public var isLooping: Bool
    public var isMuted: Bool
    public var volume: Double
    /// Optional intro animation for this cell (applied via layer-instruction ramps).
    public var transition: CellTransition?
    public var contentMode: ContentMode
    /// Per-cell framing within its cell: `zoom` (≥ 1) punches in, `panX`/`panY`
    /// (−1…1) reposition. Applied to the fill crop; ignored in `.fit` mode.
    /// Rotation is not supported for video cells (crop-based framing is axis-aligned).
    public var transform: CellTransform

    public init(
        asset: AVAsset,
        frame: CGRect,
        trim: VideoTrim = VideoTrim(),
        isLooping: Bool = false,
        isMuted: Bool = false,
        volume: Double = 1,
        transition: CellTransition? = nil,
        contentMode: ContentMode = .fill,
        transform: CellTransform = CellTransform()
    ) {
        self.asset = asset
        self.frame = frame
        self.trim = trim
        self.isLooping = isLooping
        self.isMuted = isMuted
        self.volume = volume
        self.transition = transition
        self.contentMode = contentMode
        self.transform = transform
    }
}

/// The optional background-music track to mix under the cells. The resolved
/// `AVAsset` is the builder input; the persisted counterpart is
/// `BackgroundMusicState` (the editor resolves `musicID` → asset).
public struct BackgroundMusic: @unchecked Sendable {
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
/// `overlayImage` is the pre-rendered text+sticker layer (full-canvas, transparent) —
/// present when no text overlay carries timing. It is NOT part of the video
/// composition — baking it there via `AVVideoCompositionCoreAnimationTool` crashes
/// `AVAssetReaderVideoCompositionOutput` (no Core Animation render server in that
/// pipeline / the simulator). Instead `export(bundle:…)` draws it onto each
/// composited frame at write-time, and the live preview overlays it as a CALayer
/// above the player. Either way, preview == export because the same
/// `VideoOverlayRenderer` image is used. When some text overlay does carry timing,
/// `overlayImage` is nil and `timedOverlays` is carried instead, so the export can
/// render (and cache) the overlay per frame — see `VideoComposer.overlayForFrame`.
/// `@unchecked Sendable` for the same reason as `VideoCompositionCell`: a
/// `@MainActor` editor builds the bundle and hands it to the nonisolated exporter,
/// which is the only thing that touches it from then on.
public struct VideoCompositionBundle: @unchecked Sendable {
    /// Everything needed to render the overlay for an arbitrary frame time,
    /// carried instead of a single baked image when at least one text overlay has
    /// timing. Sticker overlays are untimed and always drawn — see
    /// `VideoOverlayRenderer.overlayImage`.
    ///
    /// Plain `Sendable`: every field (`[TextOverlay]`, `[StickerOverlay]`,
    /// `CGFloat`) is already Sendable, unlike `VideoCompositionCell` /
    /// `BackgroundMusic` / the enclosing bundle, whose `@unchecked` is earned by an
    /// `AVAsset` field. No unchecked escape hatch needed here.
    ///
    /// No `canvasPx` here on purpose: it would just duplicate `bundle.renderSize`
    /// (both set from the same `output` local in `buildComposition`). The export's
    /// `overlayForFrame` derives the render size from `ExportContext.width`/
    /// `height` instead — the same ints already sizing the pixel buffer the
    /// overlay is drawn into — so there is one source of truth, not two.
    public struct TimedOverlayInputs: Sendable {
        public let textOverlays: [TextOverlay]
        public let stickerOverlays: [StickerOverlay]
        public let textFontScale: CGFloat
    }

    public let composition: AVMutableComposition
    public let videoComposition: AVMutableVideoComposition
    public let audioMix: AVMutableAudioMix
    public let duration: CMTime
    public let renderSize: CGSize
    public let overlayImage: CGImage?
    /// Non-nil only when some text overlay carries timing, in which case
    /// `overlayImage` is nil and the export selects/renders the overlay per frame
    /// instead (`VideoComposer.runExport`). `nil` for the untimed case, which
    /// keeps using the single baked `overlayImage` exactly as before.
    public let timedOverlays: TimedOverlayInputs?
}

extension VideoComposer {

    private static let compositionTimescale: CMTimeScale = 600

    /// Assembles `cells` into a collage composition sized to `canvasSize`.
    ///
    /// `textOverlays` / `stickerOverlays` are baked over the whole video via an
    /// `AVVideoCompositionCoreAnimationTool`, reusing the image-export renderers so
    /// the video matches the photo export. Any per-cell `transition` animates via
    /// layer-instruction opacity/transform ramps at the cell's start.
    /// - Parameter renderSize: the output pixel size. Defaults to `canvasSize` (the
    ///   preview resolution); the export passes the platform preset's target size
    ///   (1080p / 4K) so the written file is at the requested resolution. Cell
    ///   frames are mapped from canvas space into the render space aspect-fit +
    ///   centred (`VideoCompositionMath.renderMappedRect`), so a same-aspect target
    ///   scales uniformly and a mismatched one letterboxes.
    public func buildComposition(
        cells: [VideoCompositionCell],
        canvasSize: CGSize,
        music: BackgroundMusic? = nil,
        textOverlays: [TextOverlay] = [],
        stickerOverlays: [StickerOverlay] = [],
        textFontScale: CGFloat = 1,
        fps: Int32 = 30,
        renderSize: CGSize? = nil
    ) async throws -> VideoCompositionBundle {
        let composition = AVMutableComposition()
        let ts = Self.compositionTimescale
        let output = renderSize ?? canvasSize

        // 1) Resolve each cell's source tracks + trimmed range up front.
        var resolved: [ResolvedVideoCell] = []
        for cell in cells {
            guard let videoTrack = try await cell.asset.loadTracks(withMediaType: .video).first else { continue }
            let assetDuration = try await cell.asset.load(.duration).seconds
            let trimmed = cell.trim.clamped(toAssetDuration: assetDuration)
            guard trimmed.duration > 0 else { continue }
            // The stored size is not the seen size: a portrait clip is recorded
            // landscape with a quarter-turn in `preferredTransform`. Every piece
            // of framing below is computed in DISPLAY space, so it is resolved
            // here once — see `VideoCompositionMath.orientedSource`.
            let oriented = VideoCompositionMath.orientedSource(
                naturalSize: try await videoTrack.load(.naturalSize),
                preferredTransform: try await videoTrack.load(.preferredTransform))
            let audioTrack = try await cell.asset.loadTracks(withMediaType: .audio).first
            let range = CMTimeRange(
                start: CMTime(seconds: trimmed.start, preferredTimescale: ts),
                duration: CMTime(seconds: trimmed.duration, preferredTimescale: ts))
            resolved.append(ResolvedVideoCell(cell: cell, videoTrack: videoTrack, audioTrack: audioTrack,
                                              oriented: oriented, range: range))
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
            // the cell's canvas frame is used directly — no y-flip. The frame is
            // mapped into the render output first so export honours the target
            // resolution (identity when rendering at the canvas size).
            let mappedFrame = VideoCompositionMath.renderMappedRect(
                item.cell.frame, canvas: canvasSize, render: output)
            // Placement is worked out against the size the viewer sees, then the
            // clip's own orientation is applied first, so a portrait clip lands
            // upright instead of on its side scaled to whatever the slot allowed.
            let oriented = item.oriented
            let transform: CGAffineTransform
            switch item.cell.contentMode {
            case .fill:
                // Cover the cell (fill), honouring the cell's pan/zoom framing, then
                // clip to the source crop so nothing bleeds into a neighbour. Because
                // framing only moves/resizes the source crop, the output always
                // exactly fills the cell — no overflow at any zoom. (Centred at
                // zoom 1 / pan 0 ⇒ plain fill.)
                let cellAspect = mappedFrame.height > 0 ? mappedFrame.width / mappedFrame.height : 1
                // In display space, so pan/zoom keep meaning what the user did
                // with their fingers rather than what the file happens to store.
                let crop = VideoCompositionMath.framedCropRect(
                    source: oriented.displaySize, cellAspect: cellAspect,
                    zoom: CGFloat(item.cell.transform.zoom),
                    panX: CGFloat(item.cell.transform.panX), panY: CGFloat(item.cell.transform.panY))
                transform = oriented.orientation.concatenating(
                    VideoCompositionMath.cropFillTransform(crop: crop, in: mappedFrame))
                // The crop rectangle is read in the SOURCE's own coordinates and
                // applied before the transform, so the display-space crop has to
                // be carried back through the orientation to get there.
                layer.setCropRectangle(
                    crop.applying(oriented.orientation.inverted()), at: .zero)
            case .fit:
                transform = oriented.orientation.concatenating(
                    VideoCompositionMath.aspectFitTransform(
                        source: oriented.displaySize, in: mappedFrame))
            }
            applyPlacement(transform, transition: item.cell.transition,
                           cellFrame: mappedFrame, clipDuration: item.range.duration,
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
        videoComposition.renderSize = output
        videoComposition.frameDuration = CMTime(value: 1, timescale: fps)
        videoComposition.instructions = [instruction]

        let audioMix = AVMutableAudioMix()
        audioMix.inputParameters = audioParameters

        // Rendered at the output resolution so overlays are crisp at export size and
        // align 1:1 with the composited frames (normalized coords, so position holds).
        //
        // Untimed (the common case: every project saved before timing existed) keeps
        // the original single-baked-image path unchanged. Once any overlay carries
        // timing, baking one image up front is wrong — a caption's visibility would
        // be frozen at whatever it was when the bundle was built — so the overlays
        // are carried instead and rendered per frame during export.
        let hasTiming = textOverlays.contains { $0.startTime != nil || $0.endTime != nil }
        let overlayImage: CGImage?
        let timedOverlays: VideoCompositionBundle.TimedOverlayInputs?
        if hasTiming {
            overlayImage = nil
            timedOverlays = VideoCompositionBundle.TimedOverlayInputs(
                textOverlays: textOverlays, stickerOverlays: stickerOverlays,
                textFontScale: textFontScale)
        } else {
            overlayImage = VideoOverlayRenderer.overlayImage(
                textOverlays: textOverlays, stickerOverlays: stickerOverlays,
                canvasPx: output, textFontScale: textFontScale)
            timedOverlays = nil
        }

        return VideoCompositionBundle(composition: composition, videoComposition: videoComposition,
                                      audioMix: audioMix, duration: total, renderSize: output,
                                      overlayImage: overlayImage, timedOverlays: timedOverlays)
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

    /// Writes an arbitrary `AVAsset` out as a self-contained file.
    ///
    /// Why this exists: `PHImageManager` hands back **slo-mo** clips (and other
    /// edited/adjusted videos) as an `AVComposition`, which has no file URL — so
    /// there is nothing for `ProjectStore` to copy into a project, and the cell
    /// would resume empty. `VideoSourcePicker` calls this to normalize such an
    /// asset into a real file at import time, which keeps the invariant "every
    /// cached asset is file-backed" true everywhere downstream.
    ///
    /// Orientation and frame rate come from `videoComposition(withPropertiesOf:)`,
    /// so a portrait clip archives upright; the slo-mo timing is preserved because
    /// it's baked into the composition being read. Audio rides along via the
    /// existing mux. Still the direct reader→writer path — no `AVAssetExportSession`.
    public func archive(
        asset: AVAsset,
        codec: ExportSettings.VideoCodec = .h264,
        container: ExportPreset.VideoContainer = .mp4,
        to url: URL,
        progress: (@Sendable (Float) -> Void)? = nil,
        cancellation: ExportCancellationToken? = nil
    ) async throws {
        let duration = try await asset.load(.duration)
        let composition = AVMutableComposition()
        let range = CMTimeRange(start: .zero, duration: duration)

        guard let sourceVideo = try await asset.loadTracks(withMediaType: .video).first,
              let videoTrack = composition.addMutableTrack(
                withMediaType: .video, preferredTrackID: kCMPersistentTrackID_Invalid)
        else { throw ComposerError.noFrames }
        try videoTrack.insertTimeRange(range, of: sourceVideo, at: .zero)
        // Carry the display orientation so the derived video composition rotates it.
        videoTrack.preferredTransform = try await sourceVideo.load(.preferredTransform)

        if let sourceAudio = try await asset.loadTracks(withMediaType: .audio).first,
           let audioTrack = composition.addMutableTrack(
            withMediaType: .audio, preferredTrackID: kCMPersistentTrackID_Invalid) {
            try? audioTrack.insertTimeRange(range, of: sourceAudio, at: .zero)
        }

        let videoComposition = try await AVMutableVideoComposition.videoComposition(
            withPropertiesOf: composition)

        let bundle = VideoCompositionBundle(
            composition: composition,
            videoComposition: videoComposition,
            audioMix: AVMutableAudioMix(),      // no level changes — a faithful copy
            duration: duration,
            renderSize: videoComposition.renderSize,
            overlayImage: nil,
            timedOverlays: nil)

        try await export(bundle: bundle, codec: codec, container: container, to: url,
                         progress: progress, cancellation: cancellation)
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
        progress: (@Sendable (Float) -> Void)? = nil,
        cancellation: ExportCancellationToken? = nil
    ) async throws {
        try? FileManager.default.removeItem(at: url)
        if cancellation?.isCancelled == true { throw ComposerError.cancelled }
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
                                    timedOverlays: bundle.timedOverlays,
                                    width: width, height: height, duration: bundle.duration.seconds,
                                    outputURL: url, cancellation: cancellation)
        let exportQueue = DispatchQueue(label: "com.devron.caroullage.videoexport")
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
        let timedOverlays: VideoCompositionBundle.TimedOverlayInputs?
        let width: Int
        let height: Int
        let duration: Double
        let outputURL: URL
        let cancellation: ExportCancellationToken?
    }

    /// Tears down reader + writer and removes the partial file. Called when the
    /// user cancels mid-export (the plan's "cancel works cleanly").
    private static func abort(_ ctx: ExportContext) {
        ctx.reader.cancelReading()
        ctx.writer.cancelWriting()
        try? FileManager.default.removeItem(at: ctx.outputURL)
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
        // Single-slot cache for the timed path: frames arrive in monotonic PTS
        // order, so a run of consecutive frames between two in/out points almost
        // always shares one visible set — remembering just the last one is enough
        // to collapse that whole run to a single render, at O(1) memory instead of
        // the O(N) a dictionary keyed on every visible-set-so-far would grow to (a
        // few dozen overlapping captions at 1080×1920 is hundreds of MB of
        // full-canvas CGImages held at once otherwise). This costs a re-render only
        // when the SAME visible set recurs non-contiguously (e.g. A:[0,10) and
        // B:[5,8) revisits `{A}` at [8,10) after `{A, B}` and `{A}` already played)
        // — correct, just marginally slower than a full cache in that rare case.
        var overlayCache: OverlayCacheSlot?

        while !videoDone || !audioDone {
            if ctx.cancellation?.isCancelled == true {
                abort(ctx)
                throw ComposerError.cancelled
            }
            var progressed = false

            if !videoDone, ctx.input.isReadyForMoreMediaData {
                if let sample = ctx.output.copyNextSampleBuffer() {
                    let pts = CMSampleBufferGetPresentationTimeStamp(sample)
                    if let buffer = CMSampleBufferGetImageBuffer(sample) {
                        if let overlay = overlayForFrame(ctx, at: pts, cache: &overlayCache) {
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

    /// The single-slot overlay cache's contents: the visible-set key it was
    /// rendered for, plus the resulting image (or `nil` — "rendered, and nothing
    /// was visible" — kept distinguishable from "not cached yet", i.e. `cache ==
    /// nil`, so a caption gap doesn't force a re-render every frame).
    private struct OverlayCacheSlot {
        let key: [UUID]
        let image: CGImage?
    }

    /// Resolves the overlay image for one frame at presentation time `pts`.
    ///
    /// The untimed bundle (`ctx.timedOverlays == nil`, the common case — every
    /// project saved before timing existed) just returns the single baked
    /// `ctx.overlay`, exactly as before. Otherwise the frame's presentation time is
    /// converted to seconds once, via the same `CMTime.seconds` the export already
    /// used for progress reporting, and the overlays visible at that time (keyed on
    /// their sorted ids, a stable proxy for "what would be drawn") are compared
    /// against `cache`'s last key before rendering — so a run of frames sharing a
    /// visible set, which is most of them given monotonic PTS order, costs one
    /// render. `canvasPx` is derived from `ctx.width`/`height` (the same ints that
    /// size the pixel buffer `drawOverlay` writes into) rather than carried on
    /// `TimedOverlayInputs`, so there is one source of truth for the render size.
    private static func overlayForFrame(
        _ ctx: ExportContext, at pts: CMTime, cache: inout OverlayCacheSlot?
    ) -> CGImage? {
        guard let timed = ctx.timedOverlays else { return ctx.overlay }
        let seconds = pts.seconds
        let visible = timed.textOverlays.filter { $0.isVisible(at: seconds) }
        let key = visible.map(\.id).sorted { $0.uuidString < $1.uuidString }
        if let cache, cache.key == key { return cache.image }
        let image = VideoOverlayRenderer.overlayImage(
            textOverlays: visible, stickerOverlays: timed.stickerOverlays,
            canvasPx: CGSize(width: CGFloat(ctx.width), height: CGFloat(ctx.height)),
            textFontScale: timed.textFontScale)
        cache = OverlayCacheSlot(key: key, image: image)
        return image
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
        let oriented: VideoCompositionMath.OrientedSource
        let range: CMTimeRange
    }

    /// Sets a cell's resting placement transform, plus — if it has an intro
    /// transition — the opacity/transform ramp that animates it in.
    ///
    /// The ramp window is `[startTime, startTime + duration]`. When `startTime` is 0
    /// the cell animates in immediately (the pre-6c behaviour). When beat-sync has
    /// pushed it later, the cell is *held* in its start state (transparent for a
    /// crossfade, offset/scaled for slide/zoom) from t=0 until the beat, then
    /// animates in — so it pops onto the beat.
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
        let start = CMTime(seconds: transition.startTime, preferredTimescale: timescale)
        let window = CMTimeRange(
            start: start,
            duration: CMTimeMinimum(CMTime(seconds: transition.duration, preferredTimescale: timescale),
                                    clipDuration))
        let holdsBeforeBeat = start > .zero
        let startTransform = VideoCompositionMath.transitionStartTransform(
            style: transition.style, base: transform, cell: cellFrame)
        if startTransform != transform {
            // Hold the offset/scaled state until the beat, then ramp to rest.
            if holdsBeforeBeat { layer.setTransform(startTransform, at: .zero) }
            layer.setTransformRamp(fromStart: startTransform, toEnd: transform, timeRange: window)
        } else {
            layer.setTransform(transform, at: .zero)
        }
        let startOpacity = VideoCompositionMath.transitionStartOpacity(transition.style)
        if startOpacity != 1 {
            // Hold transparent until the beat, then fade in.
            if holdsBeforeBeat { layer.setOpacity(startOpacity, at: .zero) }
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
