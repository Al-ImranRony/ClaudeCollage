//
//  VideoOverlayRenderer.swift
//  Caroullage
//
//  Step 04 slice 4 — renders the collage's text + sticker overlays into a single
//  transparent full-canvas image that the export draws onto each frame (see
//  `VideoComposer.runExport`; the Core Animation tool crashes that pipeline). It reuses the SAME `TextRendering` /
//  `StickerRendering` helpers as the still-image export, so an overlay looks
//  identical whether the collage exports as a photo or a video (preview == export).
//

import UIKit

public enum VideoOverlayRenderer {

    /// A transparent, full-canvas image with the text (below) + sticker (above)
    /// overlays drawn in — matching `CollageRenderer`'s draw order. Returns nil when
    /// there are no overlays so the builder can skip the animation tool entirely.
    ///
    /// `textFontScale` maps the overlays' reference-canvas point sizes onto the
    /// render canvas, exactly as `RenderRequest.textFontScale` does (1 for a
    /// full-resolution render at the app's 1080-short-side sizing).
    ///
    /// - Parameter time: composition time in seconds. `nil` renders every overlay
    ///   regardless of timing, at rest — that is what the still-image export wants.
    ///   Passing a time filters to the overlays visible at that instant
    ///   (`TextOverlay.isVisible(at:)`) and draws each in its animated state
    ///   (`TextAnimationMath`), so a frame with nothing visible returns `nil` and
    ///   the caller skips the draw.
    /// - Parameter pan: when the collage pans, overlays are laid out on the strip
    ///   (`pan.stripSize`) and drawn through the camera offset at `time` of a
    ///   `duration`-second composition — the same offset the cells move by.
    public static func overlayImage(
        textOverlays: [TextOverlay],
        stickerOverlays: [StickerOverlay],
        canvasPx: CGSize,
        textFontScale: CGFloat = 1,
        at time: Double? = nil,
        pan: CanvasPan? = nil,
        duration: Double = 0
    ) -> CGImage? {
        let visibleText = time.map { t in textOverlays.filter { $0.isVisible(at: t) } }
            ?? textOverlays
        guard !visibleText.isEmpty || !stickerOverlays.isEmpty,
              canvasPx.width > 0, canvasPx.height > 0 else { return nil }

        let layoutPx = pan?.stripSize(for: canvasPx) ?? canvasPx
        let camera = pan.map { $0.cameraOffset(at: time ?? 0, duration: duration, canvas: canvasPx) }
            ?? .zero

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasPx, format: format)

        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            cg.translateBy(x: -camera.x, y: -camera.y)
            for overlay in visibleText {
                TextRendering.draw(overlay,
                                   in: TextRendering.frame(for: overlay, in: layoutPx),
                                   fontScale: textFontScale,
                                   context: cg,
                                   animation: time.map { TextAnimationMath.frame(for: overlay, at: $0) })
            }
            for overlay in stickerOverlays {
                StickerRendering.draw(overlay, in: layoutPx, context: cg)
            }
        }
        return image.cgImage
    }
}
