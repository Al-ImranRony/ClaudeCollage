//
//  ExportOptions.swift
//  ClaudeCollage
//
//  Step 04 slice 2 — the mutable user-selection state behind the Universal Export
//  sheet. Selecting a platform preset (ExportPreset) seeds these; the sheet mutates
//  them; the host editor reads them back to render + encode + save/share.
//
//  Premium gating lives here (HEVC / MOV / 4K require premium) so both the sheet UI
//  and the host clamp through the same rule. Video output size derives from the
//  platform preset — or the current canvas for Custom — scaled by the resolution tier.
//

import CoreGraphics
import Foundation

public struct ExportOptions: Equatable, Sendable {

    public enum Media: String, Sendable, CaseIterable {
        case image
        case video
    }

    /// Image output scale relative to the native canvas.
    public enum Resolution: String, Sendable, CaseIterable {
        case full
        case half
    }

    /// Video output tier. 4K is premium.
    public enum VideoResolution: String, Sendable, CaseIterable {
        case hd1080
        case uhd4k
    }

    public var platform: ExportSettings.Platform
    public var media: Media
    public var imageFormat: ExportSettings.ImageFormat  // .jpeg / .png in the UI
    public var quality: Double                          // 0.5…1.0 (JPEG only)
    public var resolution: Resolution
    public var videoContainer: ExportPreset.VideoContainer
    public var videoCodec: ExportSettings.VideoCodec
    public var videoResolution: VideoResolution

    public init(
        platform: ExportSettings.Platform,
        media: Media,
        imageFormat: ExportSettings.ImageFormat,
        quality: Double,
        resolution: Resolution,
        videoContainer: ExportPreset.VideoContainer,
        videoCodec: ExportSettings.VideoCodec,
        videoResolution: VideoResolution
    ) {
        self.platform = platform
        self.media = media
        self.imageFormat = imageFormat
        self.quality = quality
        self.resolution = resolution
        self.videoContainer = videoContainer
        self.videoCodec = videoCodec
        self.videoResolution = videoResolution
    }

    /// Seeds options from a platform preset. `supportsVideo` reflects the host
    /// editor (grid = false, carousel/video = true); an image-only preset (Print)
    /// stays on image regardless.
    public static func makeDefault(
        platform: ExportSettings.Platform,
        supportsVideo: Bool,
        isPremium: Bool
    ) -> ExportOptions {
        let preset = ExportPreset.preset(for: platform)
        let media: Media = (supportsVideo && preset.media != .image) ? .video : .image
        let options = ExportOptions(
            platform: platform,
            media: media,
            imageFormat: preset.imageFormat == .png ? .png : .jpeg,
            quality: 0.9,
            resolution: .full,
            videoContainer: preset.videoContainer,
            videoCodec: preset.videoCodec,
            videoResolution: .hd1080)
        return options.clampedForEntitlement(isPremium: isPremium)
    }

    /// Forces free-tier limits: H.264 in an MP4 container at 1080p. Premium leaves
    /// the selections untouched.
    public func clampedForEntitlement(isPremium: Bool) -> ExportOptions {
        guard !isPremium else { return self }
        var copy = self
        copy.videoCodec = .h264
        copy.videoContainer = .mp4
        copy.videoResolution = .hd1080
        return copy
    }

    /// Whether the current canvas ratio already satisfies the preset (no resize
    /// warning). Custom enforces nothing.
    public func matchesCanvas(aspectRatio: String) -> Bool {
        ExportPreset.preset(for: platform).matchesCanvas(aspectRatio: aspectRatio)
    }

    /// The concrete video output size. Uses the preset's pixel size (or the canvas
    /// for Custom), doubled for the 4K tier. Dimensions stay even for H.264.
    public func videoPixelSize(canvasSize: CGSize) -> CGSize {
        let base = ExportPreset.preset(for: platform).pixelSize ?? canvasSize
        let scale: CGFloat = videoResolution == .uhd4k ? 2 : 1
        return CGSize(width: (base.width * scale).rounded(),
                      height: (base.height * scale).rounded())
    }

    // MARK: - Mappings to the encoding services

    public var imageExporterFormat: ImageExporter.Format {
        switch imageFormat {
        case .png: return .png
        case .jpeg, .heic: return .jpeg(quality: CGFloat(quality))
        }
    }

    public var imageResolution: ImageExporter.Resolution {
        resolution == .half ? .half : .full
    }
}
