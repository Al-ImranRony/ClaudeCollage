//
//  VideoTemplateCatalog.swift
//  Caroullage
//
//  The bundled video templates. Each one is measured from a reference edit the
//  owner supplied (2026-09-27 — see
//  docs/superpowers/specs/2026-09-27-video-templates-design.md §1): geometry as
//  fractions of the frame, type sizes in reference-canvas points (the shorter
//  side is 1080), timings in seconds.
//
//  Caption text is placeholder copy the user replaces. It is deliberately our
//  own words — never a song's lyrics, which a lyric template invites.
//

import CoreGraphics
import Foundation

public enum VideoTemplateCatalog {

    /// Every bundled template, in the order the picker shows them.
    public static var all: [VideoTemplate] {
        [titleGrid, lyricStack, captionStack, travelFilmstrip]
    }

    public static func template(id: String) -> VideoTemplate? {
        all.first { $0.id == id }
    }

    // MARK: - Title Grid (reference 2: 2×2, an editorial title that fades away)

    public static var titleGrid: VideoTemplate {
        VideoTemplate(
            id: "title-grid",
            name: String(localized: "Title Grid"),
            summary: String(localized: "Four clips under a title that fades away"),
            aspectRatio: "9:16",
            layout: .grid(.fourSquare),
            textOverlays: [
                // A Didone headline sitting a little left of centre on the seam…
                TextOverlay(
                    text: String(localized: "COLLAGE"),
                    fontName: "Didot", fontSize: 118, colorHex: "#FFFFFF",
                    alignment: .center, letterSpacing: 2, lineHeight: 1, opacity: 0.94,
                    style: TextStyle(kind: .shadow, colorHex: "#000000", width: 5),
                    animation: .fade, startTime: 0, endTime: 2.6,
                    frame: CGRect(x: 0.06, y: 0.405, width: 0.76, height: 0.085)),
                // …with a thin italic line tucked under it, pushed right.
                TextOverlay(
                    text: String(localized: "of videos & photos"),
                    fontName: "Didot-Italic", fontSize: 80, colorHex: "#FFFFFF",
                    alignment: .center, letterSpacing: 1, lineHeight: 1, opacity: 0.9,
                    style: TextStyle(kind: .shadow, colorHex: "#000000", width: 4),
                    animation: .fade, startTime: 0, endTime: 2.6,
                    frame: CGRect(x: 0.2, y: 0.474, width: 0.78, height: 0.07)),
            ])
    }

    // MARK: - Lyric Stack (reference 3: three rows, kinetic word-by-word lyrics)

    public static var lyricStack: VideoTemplate {
        func lyric(_ text: String, _ start: Double, _ end: Double, y: Double, lines: Int) -> TextOverlay {
            TextOverlay(
                text: text,
                fontName: "DINCondensed-Bold", fontSize: 104, colorHex: "#F3E7CF",
                alignment: .leading, letterSpacing: 1, lineHeight: 0.9,
                style: TextStyle(kind: .shadow, colorHex: "#000000", width: 7),
                animation: .words, startTime: start, endTime: end,
                frame: CGRect(x: 0.12, y: y, width: 0.52, height: 0.058 * Double(lines) + 0.02))
        }
        return VideoTemplate(
            id: "lyric-stack",
            name: String(localized: "Lyric Stack"),
            summary: String(localized: "Three rows with word-by-word lyrics"),
            aspectRatio: "9:16",
            layout: .grid(.threeRows),
            textOverlays: [
                // Every phrase hangs off the first seam, left of centre.
                lyric(String(localized: "OH"), 0, 1.3, y: 0.262, lines: 1),
                lyric(String(localized: "HERE\nWE GO"), 1.8, 3.3, y: 0.2, lines: 2),
                lyric(String(localized: "AGAIN"), 3.3, 4.8, y: 0.262, lines: 1),
                lyric(String(localized: "WORD\nBY\nWORD"), 4.8, 7, y: 0.19, lines: 3),
            ])
    }

    // MARK: - Caption Stack (reference 4: three rows, a label that fills in word by word)

    public static var captionStack: VideoTemplate {
        func caption(_ text: String, _ start: Double, _ end: Double) -> TextOverlay {
            TextOverlay(
                text: text,
                fontName: "Georgia-Bold", fontSize: 72, colorHex: "#1C1B19",
                alignment: .center, letterSpacing: -1.5, lineHeight: 1,
                style: TextStyle(kind: .box, colorHex: "#FBF3D6", width: 30),
                animation: .wordFade, startTime: start, endTime: end,
                frame: CGRect(x: 0.06, y: 0.445, width: 0.88, height: 0.075))
        }
        return VideoTemplate(
            id: "caption-stack",
            name: String(localized: "Caption Stack"),
            summary: String(localized: "Three rows and a caption that fills in"),
            aspectRatio: "9:16",
            layout: .grid(.threeRows),
            // A hairline between the rows, as in the reference.
            borderWidth: 4,
            textOverlays: [
                caption(String(localized: "How to make these"), 0, 1.6),
                caption(String(localized: "collage videos."), 1.6, 3.4),
            ])
    }

    // MARK: - Travel Filmstrip (reference 1: panels of different widths, panning)

    /// The strip is 2.5 frames long. Panel widths, in frames:
    /// 0.62 · 0.26 · 0.58 · 0.46 · 0.58 — a wide opener, a narrow accent, and
    /// alternating mid widths, the rhythm of the reference.
    public static var travelFilmstrip: VideoTemplate {
        let extent = 2.5
        let widths: [Double] = [0.62, 0.26, 0.58, 0.46, 0.58]
        var x = 0.0
        let cells = widths.map { width -> TemplateLayoutCell in
            defer { x += width }
            return TemplateLayoutCell(frame: CGRect(x: x / extent, y: 0, width: width / extent, height: 1))
        }
        /// Frame-space x (0…2.5) → strip-normalized x.
        func sx(_ frameX: Double) -> Double { frameX / extent }

        return VideoTemplate(
            id: "travel-filmstrip",
            name: String(localized: "Travel Filmstrip"),
            summary: String(localized: "Five clips glide past like a film strip"),
            aspectRatio: "16:9",
            layout: .template(TemplateLayout(
                templateID: "video.travel-filmstrip",
                name: String(localized: "Filmstrip"),
                aspectRatio: "16:9", cells: cells)),
            pan: CanvasPan(axis: .horizontal, extent: extent),
            textOverlays: [
                // A handwritten aside by the narrow panel…
                TextOverlay(
                    text: String(localized: "Hey !"),
                    fontName: "Noteworthy-Light", fontSize: 46, colorHex: "#FFFFFF",
                    alignment: .center, letterSpacing: 2, lineHeight: 1,
                    style: TextStyle(kind: .shadow, colorHex: "#000000", width: 4),
                    frame: CGRect(x: sx(0.54), y: 0.57, width: sx(0.2), height: 0.1)),
                // …and the place, signed small at the foot of a later panel.
                TextOverlay(
                    text: String(localized: "Place name"),
                    fontName: "Noteworthy-Light", fontSize: 40, colorHex: "#FFFFFF",
                    alignment: .trailing, letterSpacing: 3, lineHeight: 1,
                    style: TextStyle(kind: .shadow, colorHex: "#000000", width: 4),
                    frame: CGRect(x: sx(1.56), y: 0.8, width: sx(0.4), height: 0.09)),
            ],
            stickerOverlays: [
                // The doodled heart above the aside. `sizeNorm` is a fraction of
                // the STRIP's width, so it reads ~5% of the frame.
                StickerOverlay(
                    stickerID: "basic.heart", symbolName: "heart", colorHex: "#FFFFFF",
                    center: CGPoint(x: sx(0.63), y: 0.2), sizeNorm: 0.02),
            ])
    }
}
