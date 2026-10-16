//
//  VideoTemplatePreviewRenderer.swift
//  Caroullage
//
//  Draws one frame of a video template for its picker card and Home poster:
//  the real layout, dressed in bundled sample photography with a slow push-in
//  (so a still reads as footage), the camera pan, and the captions animated
//  through `TextAnimationMath` → `TextRendering` — the export's own path. A
//  card therefore shows exactly what the template does, never an illustration
//  of it.
//
//  Pure: images in, image out. Callers own caching and frame pacing.
//

import UIKit

public enum VideoTemplatePreviewRenderer {

    /// How long a template's preview loop runs: long enough to play every
    /// caption and hold a beat after the last, and for a pan to travel at a
    /// readable speed.
    public static func loopDuration(for template: VideoTemplate) -> Double {
        // A sweeping glide loops seamlessly over one there-and-back.
        if let leg = template.pan?.legDuration { return 2 * leg }
        if (template.pan?.extent ?? 1) > 1 { return 7 }
        return max(4, template.captionDuration + 0.8)
    }

    /// One frame at `time` seconds into the loop, `pixelSize` wide/tall.
    /// `photos[i]` fills slot i; missing slots draw as a neutral well.
    public static func frame(
        of template: VideoTemplate, photos: [CGImage], at time: Double, pixelSize: CGSize
    ) -> CGImage? {
        guard pixelSize.width >= 1, pixelSize.height >= 1 else { return nil }
        let canvas = CanvasSize.size(forAspectRatio: template.aspectRatio)
        guard canvas.width > 0, canvas.height > 0 else { return nil }
        let loop = loopDuration(for: template)
        let t = loop > 0 ? time.truncatingRemainder(dividingBy: loop) : 0
        let layoutSize = template.pan?.stripSize(for: canvas) ?? canvas
        let cells = CollageLayoutEngine().layout(
            for: template.layout, canvasSize: layoutSize, borderWidth: CGFloat(template.borderWidth))
        let camera = template.pan?.cameraOffset(at: t, duration: loop, canvas: canvas) ?? .zero
        let scale = pixelSize.width / canvas.width

        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let image = UIGraphicsImageRenderer(size: pixelSize, format: format).image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.black.cgColor)
            cg.fill(CGRect(origin: .zero, size: pixelSize))
            cg.scaleBy(x: scale, y: scale)
            cg.translateBy(x: -camera.x, y: -camera.y)

            for (index, cell) in cells.enumerated() {
                let rect = cell.frame
                cg.saveGState()
                cg.clip(to: rect)
                if photos.indices.contains(index) {
                    draw(photos[index], in: rect, zoom: pushIn(at: t, loop: loop, phase: index), cg: cg)
                } else {
                    cg.setFillColor(Theme.Color.cellWell.cgColor)
                    cg.fill(rect)
                }
                cg.restoreGState()
            }

            for overlay in template.textOverlays where overlay.isVisible(at: t) {
                TextRendering.draw(overlay, in: TextRendering.frame(for: overlay, in: layoutSize),
                                   fontScale: 1, context: cg,
                                   animation: TextAnimationMath.frame(for: overlay, at: t))
            }
            for sticker in template.stickerOverlays {
                StickerRendering.draw(sticker, in: layoutSize, context: cg)
            }
        }
        return image.cgImage
    }

    /// The time at which a template looks most like itself — every caption up
    /// and settled — for a still poster.
    public static func posterTime(for template: VideoTemplate) -> Double {
        guard let first = template.textOverlays.first else { return 0 }
        return (first.startTime ?? 0) + TextAnimationMath.entranceDuration(for: first) + 0.05
    }

    // MARK: - Helpers

    /// A slow, seamless push-in and out — periodic over the loop, so the loop
    /// never jumps — offset per slot so the cells breathe out of step.
    private static func pushIn(at time: Double, loop: Double, phase: Int) -> CGFloat {
        guard loop > 0 else { return 1.06 }
        let angle = 2 * Double.pi * (time / loop) + Double(phase) * 1.3
        return CGFloat(1.07 + 0.05 * sin(angle))
    }

    private static func draw(_ image: CGImage, in rect: CGRect, zoom: CGFloat, cg: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        guard size.width > 0, size.height > 0 else { return }
        let fill = max(rect.width / size.width, rect.height / size.height) * zoom
        let drawn = CGSize(width: size.width * fill, height: size.height * fill)
        let origin = CGPoint(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2)
        // The context is top-down (UIKit), a CGImage draws bottom-up: flip locally.
        cg.saveGState()
        cg.translateBy(x: origin.x, y: origin.y + drawn.height)
        cg.scaleBy(x: 1, y: -1)
        cg.interpolationQuality = .medium
        cg.draw(image, in: CGRect(origin: .zero, size: drawn))
        cg.restoreGState()
    }
}
