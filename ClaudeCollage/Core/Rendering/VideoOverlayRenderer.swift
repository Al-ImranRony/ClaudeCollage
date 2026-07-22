//
//  VideoOverlayRenderer.swift
//  ClaudeCollage
//
//  Step 04 slice 4 — renders the collage's text + sticker overlays into a single
//  transparent full-canvas image that is baked over the video via
//  `AVVideoCompositionCoreAnimationTool`. It reuses the SAME `TextRendering` /
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
    public static func overlayImage(
        textOverlays: [TextOverlay],
        stickerOverlays: [StickerOverlay],
        canvasPx: CGSize,
        textFontScale: CGFloat = 1
    ) -> CGImage? {
        guard !textOverlays.isEmpty || !stickerOverlays.isEmpty,
              canvasPx.width > 0, canvasPx.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false
        let renderer = UIGraphicsImageRenderer(size: canvasPx, format: format)

        let image = renderer.image { rendererContext in
            let cg = rendererContext.cgContext
            for overlay in textOverlays {
                TextRendering.draw(overlay,
                                   in: TextRendering.frame(for: overlay, in: canvasPx),
                                   fontScale: textFontScale,
                                   context: cg)
            }
            for overlay in stickerOverlays {
                StickerRendering.draw(overlay, in: canvasPx, context: cg)
            }
        }
        return image.cgImage
    }
}
