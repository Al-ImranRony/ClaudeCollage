//
//  UniversalExportSheetView.swift
//  Caroullage
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
    /// Export credits the user has bought. Ignored when they are premium.
    public let creditBalance: Int

    public init(
        canvasSize: CGSize, canvasAspect: String, supportsVideo: Bool,
        isPremium: Bool, creditBalance: Int = 0
    ) {
        self.canvasSize = canvasSize
        self.canvasAspect = canvasAspect
        self.supportsVideo = supportsVideo
        self.isPremium = isPremium
        self.creditBalance = creditBalance
    }
}

/// How this export is being paid for.
public enum ExportPayment: Equatable, Sendable {
    /// Premium, or a free export at free-tier limits.
    case entitled
    /// The user chose to spend one credit to lift the free-tier limits.
    case credit
}

struct UniversalExportSheetView: View {

    let capabilities: ExportCapabilities
    let onSaveToPhotos: (ExportOptions, ExportPayment) -> Void
    let onQuickShare: (ExportOptions, ExportPayment) -> Void
    let onCancel: () -> Void
    let onBuyCredits: () -> Void

    @State private var options: ExportOptions
    @State private var useCredit = false

    init(capabilities: ExportCapabilities,
         onSaveToPhotos: @escaping (ExportOptions, ExportPayment) -> Void,
         onQuickShare: @escaping (ExportOptions, ExportPayment) -> Void,
         onCancel: @escaping () -> Void,
         onBuyCredits: @escaping () -> Void = {}) {
        self.capabilities = capabilities
        self.onSaveToPhotos = onSaveToPhotos
        self.onQuickShare = onQuickShare
        self.onCancel = onCancel
        self.onBuyCredits = onBuyCredits
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

    /// Premium, or a credit standing in for it on this one export.
    private var unlocked: Bool { capabilities.isPremium || useCredit }

    /// The one-time path is offered only to people who are not subscribed.
    private var showsCreditSection: Bool { !capabilities.isPremium }

    private var payment: ExportPayment { unlocked && !capabilities.isPremium ? .credit : .entitled }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    platformSection
                    if showsMediaSelector { mediaSection }
                    if mismatched { mismatchWarning }
                    if options.media == .image { imageSettings } else { videoSettings }
                    if showsCreditSection { creditSection }
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
            Text("Export").font(.themeHeadline).foregroundStyle(Color.themeTextPrimary)
            Spacer()
            Button("Cancel", action: onCancel).opacity(0).accessibilityHidden(true)
        }
        .padding()
        .foregroundStyle(Color.themeAccentStrong)
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
                Text(info.title).font(.themeCaption)
            }
            .foregroundStyle(selected ? Color.themeTextOnAccent : Color.themeTextPrimary)
            .frame(width: 74, height: 74)
            // The selected fill is `accentStrong` rather than the indigo: a
            // filled pill is the segmented control's pattern, and the caption
            // under the glyph needs `textOnAccent` on the ink to stay legible.
            .background(selected ? Color.themeAccentStrong : Color.themeSurface)
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
                        .font(.themeSubheadline).foregroundStyle(Color(Theme.Color.textSecondary))
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
            if unlocked {
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
                    .font(.themeSubheadline).foregroundStyle(Color(Theme.Color.textPrimary))
                Text("4K & HEVC come with Premium — or one credit.")
                    .font(.themeCaption).foregroundStyle(Color(Theme.Color.textSecondary))
            }
            Text("Filters, text, stickers & transitions are always baked in.")
                .font(.themeCaption).foregroundStyle(Color(Theme.Color.textSecondary))
        }
    }

    // MARK: - One-time credits

    /// The path for someone who will not subscribe: pay once, export once.
    private var creditSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(String(localized: "One-time"))

            if capabilities.creditBalance > 0 {
                Toggle(isOn: $useCredit.animation(
                    .easeOut(duration: Theme.Motion.duration(Theme.Motion.quick))
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use 1 credit for this export")
                            .font(.themeSubheadline).foregroundStyle(Color.themeTextPrimary)
                        Text("\(capabilities.creditBalance) left · full resolution, 4K & HEVC, no watermark")
                            .font(.themeCaption).foregroundStyle(Color.themeTextSecondary)
                    }
                }
                .tint(Color.themeAccentStrong)
                .accessibilityIdentifier("exportUseCreditToggle")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Not subscribing? Buy a single credit and export this one at full quality.")
                        .font(.themeCaption).foregroundStyle(Color.themeTextSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Button("Get Credits") {
                        Haptics.tap()
                        onBuyCredits()
                    }
                    .font(.themeCallout)
                    .foregroundStyle(Color.themeAccentStrong)
                    .accessibilityIdentifier("exportGetCreditsButton")
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themeSurface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.md, style: .continuous))
    }

    private var mismatchWarning: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
            Text("Your canvas is \(CanvasSize.normalize(capabilities.canvasAspect)) but this preset prefers \(ExportPreset.preset(for: options.platform).enforcedAspect ?? "the current size"). It will export anyway, scaled to fill the frame.")
                .font(.themeCaption)
        }
        .foregroundStyle(Color.themeWarning)
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.themeWarning.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .accessibilityIdentifier("exportMismatchWarning")
    }

    // MARK: - Section 3: actions

    private var actionBar: some View {
        VStack(spacing: 10) {
            Button {
                onSaveToPhotos(finalOptions, payment)
            } label: {
                Label("Save to Photos", systemImage: "square.and.arrow.down")
                    .font(.themeHeadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.themeAccentStrong)
                    .foregroundStyle(Color.themeTextOnAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportSaveButton")

            Button {
                onQuickShare(finalOptions, payment)
            } label: {
                Label("Quick Share", systemImage: "square.and.arrow.up")
                    .font(.themeHeadline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.themeSurface)
                    .foregroundStyle(Color.themeAccentStrong)
                    .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .buttonStyle(.plain)
            .accessibilityIdentifier("exportShareButton")
        }
        .padding(20)
    }

    /// Final selections, defensively clamped to whatever the user is entitled to
    /// right now — which a spent credit lifts for this one export.
    private var finalOptions: ExportOptions {
        options.clampedForEntitlement(isPremium: unlocked)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.themeCaption).fontWeight(.semibold)
            .foregroundStyle(Color(Theme.Color.textSecondary))
    }
}
