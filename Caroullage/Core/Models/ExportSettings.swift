//
//  ExportSettings.swift
//  Caroullage
//
//  Per-project export configuration. Stub for Step 00.
//

import Foundation

public struct ExportSettings: Codable, Sendable, Equatable {

    public enum Platform: String, Codable, Sendable, CaseIterable {
        case instagramPost
        case instagramStory
        case tiktok
        case youtube
        case x
        case whatsapp
        case print
        case custom
    }

    public enum ImageFormat: String, Codable, Sendable, CaseIterable {
        case jpeg
        case png
        case heic
    }

    public enum VideoCodec: String, Codable, Sendable, CaseIterable {
        case h264
        case hevc
    }

    public var platform: Platform
    public var imageFormat: ImageFormat
    public var videoCodec: VideoCodec
    public var includeWatermark: Bool

    public init(
        platform: Platform = .instagramPost,
        imageFormat: ImageFormat = .jpeg,
        videoCodec: VideoCodec = .h264,
        includeWatermark: Bool = true
    ) {
        self.platform = platform
        self.imageFormat = imageFormat
        self.videoCodec = videoCodec
        self.includeWatermark = includeWatermark
    }
}
