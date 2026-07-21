//
//  UniversalExportSheetView.swift
//  ClaudeCollage
//
//  Step 04 slice 2 — the Universal Export sheet (the project's most important
//  deliverable). One SwiftUI form, presented via UIHostingController from every
//  editor, that collects a platform preset + quality settings and hands the finished
//  `ExportOptions` back to the host to render, encode, and save/share.
//
//  Three sections mirror the spec: (1) platform/format presets, (2) quality
//  settings (image or video), (3) Save to Photos / Quick Share. The host owns the
//  actual export work + progress; this view only collects intent.
//

import SwiftUI

/// What the presenting editor can produce, so the sheet shows the right options.
public struct ExportCapabilities: Equatable {
    public let canvasSize: CGSize
    public let canvasAspect: String
    public let supportsVideo: Bool
    public let isPremium: Bool

    public init(canvasSize: CGSize, canvasAspect: String, supportsVideo: Bool, isPremium: Bool) {
        self.canvasSize = canvasSize
        self.canvasAspect = canvasAspect
        self.supportsVideo = supportsVideo
        self.isPremium = isPremium
    }
}

struct UniversalExportSheetView: View {

    let capabilities: ExportCapabilities
    let onSaveToPhotos: (ExportOptions) -> Void
    let onQuickShare: (ExportOptions) -> Void
    let onCancel: () -> Void

    @State private var options: ExportOptions

    init(capabilities: ExportCapabilities,
         onSaveToPhotos: @escaping (ExportOptions) -> Void,
         onQuickShare: @escaping (ExportOptions) -> Void,
         onCancel: @escaping () -> Void) {
        self.capabilities = capabilities
        self.onSaveToPhotos = onSaveToPhotos
        self.onQuickShare = onQuickShare
        self.onCancel = onCancel
        _options = State(initialValue: ExportOptions.makeDefault(
            platform: .instagramPost,
            supportsVideo: capabilities.supportsVideo,
            isPremium: capabilities.isPremium))
    }

    private struct PlatformInfo: Identifiable {
        let id: ExportSettings.Platform
        let title: String
        let symbol: String
    }

    private let platforms: [PlatformInfo] = [
        .init(id: .instagramPost, title: "IG Post", symbol: "camera"),
        .init(id: .instagramStory, title: "Story", symbol: "iphone"),
        .init(id: .tiktok, title: "TikTok", symbol: "music.note"),
        .init(id: .youtube, title: "YouTube", symbol: "play.rectangle"),
        .init(id: .x, title: "X", symbol: "xmark.square"),
        .init(id: .whatsapp, title: "WhatsApp", symbol: "message"),
        .init(id: .print, title: "Print", symbol: "printer"),
        .init(id: .custom, title: "Custom", symbol: "slider.horizontal.3"),
    ]

    private var showsMediaSelector: Bool {
        capabilities.supportsVideo && ExportPreset.preset(for: options.platform).media == .both
    }

    private var mismatched: Bool {
        !options.matchesCanvas(aspectRatio: capabilities.canvasAspect)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    platformSection
                    if showsMediaSelector { mediaSection }
                    if mismatched { mismatchWarning }
                    if options.media == .image { imageSettings } else { videoSettings }
                }
                .padding(20)
            }
            actionBar
        }
        .background(Color(Theme.Color.background).ignoresSafeArea())
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .accessibilityIdentifier("exportCancelButton")
            Spacer()
            Text("Export").font(.headline).foregroundStyle(Color(Theme.Color.textPrimary))
            Spacer()
            Button("Cancel", action: onCancel).opacity(0).accessibilityHidden(true)
        }
        .padding()
        .foregroundStyle(Color(Theme.Color.accent))
    }

    // MARK: - Section 1: platform presets

    private var platformSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Platform")
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(platforms) { info in
                        platformTile(info)
                    }
                }
            }
        }
    }

    private func platformTile(_ info: PlatformInfo) -> some View {
        let selected = info.id == options.platform
        return Button {
            options = ExportOptions.makeDefault(platform: info.id,
                                                supportsVideo: capabilities.supportsVideo,
                                                isPremium: capabilities.isPremium)
            Haptics.tap()
        } label: {
            VStack(spacing: 6) {
                Image(systemName: info.symbol)
                    .font(.system(size: 22))
                    .frame(width: 54, height: 40)
                Text(info.title).font(.caption)
            }
            .foregroundStyle(selected ? Color(Theme.Color.textOnAccent) : Color(Theme.Color.textPrimary))
            .frame(width: 74, height: 74)
            .background(selected ? Color(Theme.Color.accent) : Color(Theme.Color.surface))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("exportPlatform-\(info.id.rawValue)")
    }

    // MARK: - Media (image vs video)

    private var mediaSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Media")
            Picker("Media", selection: $options.media) {
                Text("Image").tag(ExportOptions.Media.image)
                Text("Video").tag(ExportOptions.Media.video)
            }
            .pickerStyle(.segmented)
        }
    }

    // MARK: - Section 2: quality

    private var imageSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Image Quality")
            Picker("Format", selection: $options.imageFormat) {
                Text("JPEG").tag(ExportSettings.ImageFormat.jpeg)
                Text("PNG").tag(ExportSettings.ImageFormat.png)
            }
            .pickerStyle(.segmented)

            if options.imageFormat == .jpeg {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Quality \(Int(options.quality * 100))%")
                        .font(.subheadline).foregroundStyle(Color(Theme.Color.textSecondary))
                    Slider(value: $options.quality, in: 0.5...1.0)
                        .tint(Color(Theme.Color.accent))
                        .accessibilityIdentifier("exportQualitySlider")
                }
            }

            Picker("Resolution", selection: $options.resolution) {
                Text("Full").tag(ExportOptions.Resolution.full)
                Text("Half").tag(ExportOptions.Resolution.half)
            }
            .pickerStyle(.segmented)
        }
    }

    private var videoSettings: some View {
        VStack(alignment: .leading, spacing: 16) {
            sectionTitle("Video Quality")
            if capabilities.isPremium {
                Picker("Resolution", selection: $options.videoResolution) {
                    Text("1080p").tag(ExportOptions.VideoResolution.hd1080)
                    Text("4K").tag(ExportOptions.VideoResolution.uhd4k)
                }
                .pickerStyle(.segmented)
                Picker("Format", selection: $options.videoCodec) {
                    Text("MP4 · H.264").tag(ExportSettings.VideoCodec.h264)
                    Text("MOV · HEVC").tag(ExportSettings.VideoCodec.hevc)
                }
                .pickerStyle(.segmented)
                .onChange(of: options.videoCodec) { _, codec in
                    options.videoContainer = codec == .hevc ? .mov : .mp4
                }
            } else {
                Text("1080p · MP4 (H.264)")
                    .font(.subheadline).foregroundStyle(Color(Theme.Color.textPrimary))
                Text("Upgrade to Premium for 4K & HEVC")
                    .font(.caption).foregroundStyle(Color(Theme.Color.textSecondary))
            }
            Text("Filters, text, stickers & transitions are always baked in.")
                .font(.caption).foregroundStyle(Color(Theme.Color.textSecondary))
        }
    }

    private var mismatchWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Your canvas is \(CanvasSize.normalize(capabilities.canvasAspect)) but this preset prefers \(ExportPreset.preset(for: options.platform).enforcedAspect ?? "the current size"). It will export anyway, scaled to fill the frame.")
                .font(.caption)
        }
        .foregroundStyle(Color(Theme.Color.accent))
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(Theme.Color.accentSoft))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("exportMismatchWarning")
    }

    // MARK: - Section 3: actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                onSaveToPhotos(finalOptions)
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(Theme.Color.accent))
                    .foregroundStyle(Color(Theme.Color.textOnAccent))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportSaveButton")

            Button {
                onQuickShare(finalOptions)
            } label: {
                Label("Quick Share", systemImage: "square.and.arrow.up")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color(Theme.Color.surface))
                    .foregroundStyle(Color(Theme.Color.accent))
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportShareButton")
        }
        .padding(20)
    }

    /// Final selections, defensively clamped to the user's entitlement.
    private var finalOptions: ExportOptions {
        options.clampedForEntitlement(isPremium: capabilities.isPremium)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.caption).fontWeight(.semibold)
            .foregroundStyle(Color(Theme.Color.textSecondary))
    }
}
