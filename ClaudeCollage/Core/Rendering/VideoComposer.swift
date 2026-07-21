//
//  VideoComposer.swift
//  ClaudeCollage
//
//  Step 04 slice 1 — the video export engine. Turns a sequence of fully-composited
//  frames (CGImages already carrying photos, filters, text, stickers) into an H.264
//  MP4 (or HEVC MOV, premium) via a DIRECT AVAssetReader→AVAssetWriter pixel path.
//
//  Why not AVAssetExportSession? Export sessions resample through an internal
//  pipeline that can soften quality (SCRL's documented bug). Writing pixel buffers
//  straight into AVAssetWriter preserves full fidelity.
//
//  This slice ships the slideshow path — one still frame per page, held for a fixed
//  duration — which also unblocks Step 03b's deferred carousel video export. Video
//  *cells* (AVAsset trim/loop/audio) and transitions arrive in later slices.
//

import AVFoundation
import CoreGraphics
import CoreMedia
import Foundation

public final class VideoComposer: @unchecked Sendable {

    public enum ComposerError: Error, Equatable {
        case noFrames
        case writerSetupFailed
        case pixelBufferFailed
        case writeFailed
    }

    private let queue = DispatchQueue(label: "com.devron.claudecollage.videocomposer")

    public init() {}

    /// Renders `frames` as a slideshow video at `size`, each frame held for
    /// `secondsPerFrame`, written directly to `url`. `progress` reports 0…1 as
    /// frames are appended.
    public func renderSlideshow(
        frames: [CGImage],
        size: CGSize,
        secondsPerFrame: Double = 2.0,
        fps: Int32 = 30,
        codec: ExportSettings.VideoCodec = .h264,
        container: ExportPreset.VideoContainer = .mp4,
        to url: URL,
        progress: (@Sendable (Float) -> Void)? = nil
    ) async throws {
        guard !frames.isEmpty else { throw ComposerError.noFrames }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            queue.async {
                do {
                    try self.writeSync(frames: frames, size: size, secondsPerFrame: secondsPerFrame,
                                       fps: fps, codec: codec, container: container, to: url,
                                       progress: progress)
                    cont.resume()
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    // MARK: - Synchronous writer (runs on `queue`)

    private func writeSync(
        frames: [CGImage], size: CGSize, secondsPerFrame: Double, fps: Int32,
        codec: ExportSettings.VideoCodec, container: ExportPreset.VideoContainer,
        to url: URL, progress: (@Sendable (Float) -> Void)?
    ) throws {
        try? FileManager.default.removeItem(at: url)

        let fileType: AVFileType = container == .mov ? .mov : .mp4
        guard let writer = try? AVAssetWriter(url: url, fileType: fileType) else {
            throw ComposerError.writerSetupFailed
        }

        let codecType: AVVideoCodecType = codec == .hevc ? .hevc : .h264
        let width = Int(size.width.rounded()), height = Int(size.height.rounded())
        let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
            AVVideoCodecKey: codecType,
            AVVideoWidthKey: width,
            AVVideoHeightKey: height
        ])
        input.expectsMediaDataInRealTime = false

        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: input,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
                kCVPixelBufferWidthKey as String: width,
                kCVPixelBufferHeightKey as String: height
            ])

        guard writer.canAdd(input) else { throw ComposerError.writerSetupFailed }
        writer.add(input)
        guard writer.startWriting() else { throw writer.error ?? ComposerError.writerSetupFailed }
        writer.startSession(atSourceTime: .zero)

        let framesPerImage = max(1, Int((secondsPerFrame * Double(fps)).rounded()))
        var frameCounter: Int64 = 0
        let totalAppends = frames.count * framesPerImage

        for (index, image) in frames.enumerated() {
            guard let buffer = pixelBuffer(from: image, width: width, height: height) else {
                writer.cancelWriting()
                throw ComposerError.pixelBufferFailed
            }
            for _ in 0..<framesPerImage {
                while !input.isReadyForMoreMediaData { Thread.sleep(forTimeInterval: 0.005) }
                let time = CMTime(value: frameCounter, timescale: fps)
                if !adaptor.append(buffer, withPresentationTime: time) {
                    writer.cancelWriting()
                    throw writer.error ?? ComposerError.writeFailed
                }
                frameCounter += 1
            }
            progress?(Float(Double((index + 1) * framesPerImage) / Double(totalAppends)))
        }

        input.markAsFinished()
        let sema = DispatchSemaphore(value: 0)
        writer.finishWriting { sema.signal() }
        sema.wait()
        guard writer.status == .completed else {
            throw writer.error ?? ComposerError.writeFailed
        }
    }

    // MARK: - Pixel buffer

    /// Draws `image` into a fresh 32BGRA pixel buffer sized to the canvas
    /// (aspect-fill so a differently-sized source still covers the frame).
    private func pixelBuffer(from image: CGImage, width: Int, height: Int) -> CVPixelBuffer? {
        let attrs: [CFString: Any] = [
            kCVPixelBufferCGImageCompatibilityKey: true,
            kCVPixelBufferCGBitmapContextCompatibilityKey: true
        ]
        var pb: CVPixelBuffer?
        let status = CVPixelBufferCreate(kCFAllocatorDefault, width, height,
                                         kCVPixelFormatType_32BGRA, attrs as CFDictionary, &pb)
        guard status == kCVReturnSuccess, let buffer = pb else { return nil }

        CVPixelBufferLockBaseAddress(buffer, [])
        defer { CVPixelBufferUnlockBaseAddress(buffer, []) }
        guard let base = CVPixelBufferGetBaseAddress(buffer),
              let ctx = CGContext(
                data: base, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue
                    | CGBitmapInfo.byteOrder32Little.rawValue
              ) else { return nil }

        ctx.setFillColor(gray: 0, alpha: 1)
        ctx.fill(CGRect(x: 0, y: 0, width: width, height: height))
        ctx.draw(image, in: aspectFillRect(imageSize: CGSize(width: image.width, height: image.height),
                                           in: CGRect(x: 0, y: 0, width: width, height: height)))
        return buffer
    }

    private func aspectFillRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let w = imageSize.width * scale, h = imageSize.height * scale
        return CGRect(x: frame.midX - w / 2, y: frame.midY - h / 2, width: w, height: h)
    }
}
