//
//  VideoStartView.swift
//  Caroullage
//
//  The "new video collage" sheet: pick a template or start blank at a chosen
//  shape. Before this, Video opened a blank 4:5 two-up with no way to reach
//  9:16 — the shape nearly every short-form video is posted at.
//
//  Template cards play their template live (`VideoTemplatePreviewRenderer`
//  over bundled sample photography, through the export's own text and pan
//  code), so what the user taps is what the template does. Reduce Motion shows
//  a still at the moment the template looks most like itself.
//

import SwiftUI

struct VideoStartView: View {

    let templates: [VideoTemplate]
    let onPickTemplate: (VideoTemplate) -> Void
    let onPickBlank: (String) -> Void
    let onCancel: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    /// A tall template card grows with its words — at a fixed 150pt the
    /// accessibility sizes broke "4 clips" and "Caption Stack" mid-word — up to
    /// a width that still leaves the next card peeking in.
    @ScaledMetric(relativeTo: .subheadline) private var scaledCardWidth: CGFloat = 150
    private var tallCardWidth: CGFloat { min(scaledCardWidth, 260) }
    /// Same for the blank tiles: wider minimum, fewer columns.
    @ScaledMetric(relativeTo: .subheadline) private var blankTileMinWidth: CGFloat = 72

    /// Blank canvases, tallest first — the order people post in.
    static let blankAspects: [(ratio: String, title: LocalizedStringKey, subtitle: LocalizedStringKey)] = [
        ("9:16", "Story", "Reels · TikTok"),
        ("4:5", "Portrait", "Feed"),
        ("1:1", "Square", "Feed"),
        ("16:9", "Wide", "YouTube"),
    ]

    private var tallTemplates: [VideoTemplate] { templates.filter { !$0.isWide } }
    private var wideTemplates: [VideoTemplate] { templates.filter(\.isWide) }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Templates") {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(alignment: .top, spacing: 12) {
                                ForEach(tallTemplates) { template in
                                    templateCard(template, previewWidth: tallCardWidth)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                        ForEach(wideTemplates) { template in
                            templateCard(template, previewWidth: nil)
                                .padding(.horizontal, 16)
                        }
                    }
                    section("Start Blank") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: min(blankTileMinWidth, 300)), spacing: 12)], spacing: 12) {
                            ForEach(Self.blankAspects, id: \.ratio) { aspect in
                                blankTile(aspect.ratio, title: aspect.title, subtitle: aspect.subtitle)
                            }
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.vertical, 12)
            }
        }
        .background(Color(Theme.Color.background).ignoresSafeArea())
    }

    // MARK: - Pieces

    private var header: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .accessibilityIdentifier("videoStartCancelButton")
            Spacer()
            Text("New Video")
                .font(.themeHeadline)
                .foregroundStyle(Color.themeTextPrimary)
            Spacer()
            Button("Cancel", action: onCancel).opacity(0)   // balances the title
                .accessibilityHidden(true)
        }
        .padding()
        .foregroundStyle(Color.themeAccentStrong)
        // Capped at the largest standard size, the way a navigation bar caps
        // its title: "Cancel · New Video" must stay one line (the export
        // sheet's header does the same). The content beneath scales fully.
        .dynamicTypeSize(...DynamicTypeSize.xxxLarge)
    }

    private func section<Content: View>(
        _ title: LocalizedStringKey, @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.themeTitle2)
                .foregroundStyle(Color.themeTextPrimary)
                .padding(.horizontal, 16)
                .accessibilityAddTraits(.isHeader)
            content()
        }
    }

    /// A template's live preview, name, one-line summary and what it asks for.
    /// `previewWidth` nil = full width (the wide templates).
    private func templateCard(_ template: VideoTemplate, previewWidth: CGFloat?) -> some View {
        Button {
            onPickTemplate(template)
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                TemplatePreview(template: template, animates: !reduceMotion)
                    .aspectRatio(template.aspect, contentMode: .fit)
                    .frame(width: previewWidth)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(alignment: .bottomLeading) {
                        Label(clipCount(template), systemImage: "film.stack")
                            .font(.themeCaption.weight(.semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            // Dark enough to hold white text over the
                            // brightest sample frame (the accessibility audit
                            // samples the pixels behind it).
                            .background(.black.opacity(0.72), in: Capsule())
                            .padding(8)
                    }
                Text(template.name)
                    .font(.themeHeadline)
                    .foregroundStyle(Color.themeTextPrimary)
                Text(template.summary)
                    .font(.themeSubheadline)
                    .foregroundStyle(Color.themeTextSecondary)
                    // Two lines keep the row even; at the accessibility sizes two
                    // lines hold only a few words, so the summary may run longer.
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? 6 : 2,
                               reservesSpace: previewWidth != nil)
                    .multilineTextAlignment(.leading)
            }
            .frame(width: previewWidth, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        // Every part is already localized; the list itself is not copy.
        .accessibilityLabel(Text(verbatim: "\(template.name), \(template.summary), \(clipCount(template))"))
        .accessibilityHint(Text("Opens the template with empty slots for your clips"))
        .accessibilityIdentifier("videoTemplate-\(template.id)")
    }

    private func clipCount(_ template: VideoTemplate) -> String {
        String(localized: "\(template.slotCount) clips")
    }

    private func blankTile(_ ratio: String, title: LocalizedStringKey, subtitle: LocalizedStringKey) -> some View {
        let size = CanvasSize.size(forAspectRatio: ratio)
        return Button {
            onPickBlank(ratio)
        } label: {
            VStack(spacing: 6) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.themeControlFill)
                    RoundedRectangle(cornerRadius: 4, style: .continuous)
                        .strokeBorder(Color.themeTextPrimary, lineWidth: 2)
                        .aspectRatio(size.width / max(1, size.height), contentMode: .fit)
                        .padding(14)
                }
                .frame(height: 76)
                Text(title)
                    .font(.themeSubheadline.weight(.semibold))
                    .foregroundStyle(Color.themeTextPrimary)
                Text(verbatim: ratio)
                    .font(.themeCaption)
                    .foregroundStyle(Color.themeTextSecondary)
                Text(subtitle)
                    .font(.themeCaption)
                    .foregroundStyle(Color.themeTextSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableCardStyle())
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("videoBlank-\(ratio)")
    }
}

// MARK: - Live preview

/// Plays one template in a loop. Frames are drawn at ~20 fps — plenty for
/// captions and a slow pan — and at twice the point size, not the screen's
/// full scale: these are thumbnails in motion, and the lower pixel count is
/// what keeps three of them smooth together.
private struct TemplatePreview: View {
    let template: VideoTemplate
    let animates: Bool

    @State private var photos: [CGImage] = []

    var body: some View {
        GeometryReader { proxy in
            let pixelSize = CGSize(width: proxy.size.width * 2, height: proxy.size.height * 2)
            Group {
                if animates {
                    TimelineView(.animation(minimumInterval: 1.0 / 20)) { context in
                        frame(at: context.date.timeIntervalSinceReferenceDate, pixelSize: pixelSize)
                    }
                } else {
                    frame(at: VideoTemplatePreviewRenderer.posterTime(for: template), pixelSize: pixelSize)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
        }
        .background(Color.black)
        .onAppear { photos = VideoTemplateSamplePhotos.photos(for: template) }
        .accessibilityHidden(true)
    }

    @ViewBuilder
    private func frame(at time: Double, pixelSize: CGSize) -> some View {
        if let image = VideoTemplatePreviewRenderer.frame(
            of: template, photos: photos, at: time, pixelSize: pixelSize) {
            Image(decorative: image, scale: 2)
                .resizable()
        } else {
            Color.black
        }
    }
}

/// The bundled sample photography each template's preview is dressed in —
/// chosen to echo each reference (a beach for the title grid, outfits for the
/// lyric stack, a travel day for the caption stack and the filmstrip).
/// Decoded once, small: these fill thumbnails, not the canvas.
@MainActor
enum VideoTemplateSamplePhotos {

    private static var cache: [String: [CGImage]] = [:]

    static let names: [String: [String]] = [
        "title-grid": ["sample_travel_01", "sample_travel_02", "sample_friends_03", "sample_travel_04"],
        "lyric-stack": ["sample_friends_02", "sample_portrait_06", "sample_seasonal_01"],
        "caption-stack": ["sample_portrait_02", "sample_food_02", "sample_travel_03"],
        "travel-filmstrip": ["sample_travel_04", "sample_portrait_04", "sample_travel_02",
                             "sample_seasonal_02", "sample_travel_03"],
    ]

    static func photos(for template: VideoTemplate, maxSide: CGFloat = 480) -> [CGImage] {
        let key = "\(template.id)@\(Int(maxSide))"
        if let cached = cache[key] { return cached }
        let images = (names[template.id] ?? []).compactMap { name -> CGImage? in
            guard let image = SampleContentCatalog.shared.image(named: name)?.cgImage else { return nil }
            return downsample(image, maxSide: maxSide)
        }
        cache[key] = images
        return images
    }

    private static func downsample(_ image: CGImage, maxSide: CGFloat) -> CGImage {
        let longest = CGFloat(max(image.width, image.height))
        guard longest > maxSide else { return image }
        let scale = maxSide / longest
        let size = CGSize(width: CGFloat(image.width) * scale, height: CGFloat(image.height) * scale)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: size, format: format).image { _ in
            UIImage(cgImage: image).draw(in: CGRect(origin: .zero, size: size))
        }.cgImage ?? image
    }
}

/// Press feedback for a whole card — a soft scale, like the rest of the app's
/// pressable surfaces.
private struct PressableCardStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(.spring(response: 0.25, dampingFraction: 0.8), value: configuration.isPressed)
    }
}

extension VideoTemplate {
    /// Width over height of the template's frame.
    var aspect: CGFloat {
        let size = CanvasSize.size(forAspectRatio: aspectRatio)
        return size.height > 0 ? size.width / size.height : 1
    }

    /// Landscape templates get a full-width card; tall ones share a row.
    var isWide: Bool { aspect > 1 }
}
