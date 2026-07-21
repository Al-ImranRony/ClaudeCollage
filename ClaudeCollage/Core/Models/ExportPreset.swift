//
//  ExportPreset.swift
//  ClaudeCollage
//
//  Step 04 slice 1 — the platform/format presets that back Section 1 of the
//  universal export sheet. Selecting a platform auto-fills the output size, media
//  kind, and default video/image format. Pure value logic (no I/O) so it's fully
//  unit-testable and shared by every editor's export path.
//
//  Sizing follows the spec table: Story/TikTok/WhatsApp = 1080×1920 (9:16),
//  YouTube = 1920×1080 (16:9), Twitter/X = 1280×720 (720p, intentionally lower),
//  Instagram Post = 1080×1080 (1:1), Print = 4:3 JPEG image-only, Custom enforces
//  nothing (uses the current canvas).
//

import CoreGraphics
import Foundation

public struct ExportPreset: Sendable, Equatable {

    /// What the platform accepts. `both` means the editor's own content decides.
    public enum Media: Sendable, Equatable {
        case image
        case video
        case both
    }

    public enum VideoContainer: String, Sendable, Equatable {
        case mp4
        case mov
    }

    public let platform: ExportSettings.Platform
    /// The enforced canvas aspect ("9:16"), or nil for Custom (no enforcement).
    public let enforcedAspect: String?
    /// The target output size, or nil for Custom (uses the current canvas).
    public let pixelSize: CGSize?
    public let media: Media
    public let videoContainer: VideoContainer
    public let videoCodec: ExportSettings.VideoCodec
    public let imageFormat: ExportSettings.ImageFormat

    public init(
        platform: ExportSettings.Platform,
        enforcedAspect: String?,
        pixelSize: CGSize?,
        media: Media,
        videoContainer: VideoContainer = .mp4,
        videoCodec: ExportSettings.VideoCodec = .h264,
        imageFormat: ExportSettings.ImageFormat = .jpeg
    ) {
        self.platform = platform
        self.enforcedAspect = enforcedAspect
        self.pixelSize = pixelSize
        self.media = media
        self.videoContainer = videoContainer
        self.videoCodec = videoCodec
        self.imageFormat = imageFormat
    }

    /// True when this preset imposes no aspect (Custom) or the given canvas ratio
    /// already matches the enforced one — i.e. no "resize canvas?" warning is needed.
    public func matchesCanvas(aspectRatio: String) -> Bool {
        guard let enforcedAspect else { return true }
        return CanvasSize.normalize(enforcedAspect) == CanvasSize.normalize(aspectRatio)
    }

    /// The canonical preset for a platform.
    public static func preset(for platform: ExportSettings.Platform) -> ExportPreset {
        switch platform {
        case .instagramPost:
            return ExportPreset(platform: platform, enforcedAspect: "1:1",
                                pixelSize: CGSize(width: 1080, height: 1080), media: .both)
        case .instagramStory:
            return ExportPreset(platform: platform, enforcedAspect: "9:16",
                                pixelSize: CGSize(width: 1080, height: 1920), media: .both)
        case .tiktok:
            return ExportPreset(platform: platform, enforcedAspect: "9:16",
                                pixelSize: CGSize(width: 1080, height: 1920), media: .both)
        case .youtube:
            return ExportPreset(platform: platform, enforcedAspect: "16:9",
                                pixelSize: CGSize(width: 1920, height: 1080), media: .video)
        case .x:
            return ExportPreset(platform: platform, enforcedAspect: "16:9",
                                pixelSize: CGSize(width: 1280, height: 720), media: .both)
        case .whatsapp:
            return ExportPreset(platform: platform, enforcedAspect: "9:16",
                                pixelSize: CGSize(width: 1080, height: 1920), media: .both)
        case .print:
            return ExportPreset(platform: platform, enforcedAspect: "4:3",
                                pixelSize: CanvasSize.size(forAspectRatio: "4:3"),
                                media: .image, imageFormat: .jpeg)
        case .custom:
            return ExportPreset(platform: platform, enforcedAspect: nil,
                                pixelSize: nil, media: .both)
        }
    }
}
