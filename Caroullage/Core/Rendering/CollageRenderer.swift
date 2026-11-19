//
//  CollageRenderer.swift
//  Caroullage
//
//  Step 01 — Core Graphics compositor for the ONE-SHOT paths only: export and
//  gallery thumbnails. The live editor no longer calls this per gesture frame;
//  it uses a GPU-composited layer tree (see CanvasView). Images passed here are
//  already downsampled and filtered upstream, so this is a pure compositor —
//  no Core Image, no full-resolution decode.
//
//  Backend-agnostic by design: a Metal path can replace it in Step 02 without
//  changing callers.
//

import UIKit

/// One cell's compositing inputs, already resolved to absolute canvas pixels
/// and already colour-filtered.
public struct RenderCell: Sendable {
    public let frame: CGRect
    public let image: CGImage?
    public let transform: CellTransform
    public let cornerRadius: CGFloat
    public let clipShape: CellClipShape

    public init(
        frame: CGRect,
        image: CGImage?,
        transform: CellTransform,
        cornerRadius: CGFloat,
        clipShape: CellClipShape = .rectangle
    ) {
        self.frame = frame
        self.image = image
        self.transform = transform
        self.cornerRadius = cornerRadius
        self.clipShape = clipShape
    }
}

/// A full canvas compositing request.
public struct RenderRequest: Sendable {
    public let canvasSize: CGSize
    public let background: CollageBackground
    public let cells: [RenderCell]
    /// Text zones drawn (in order) above the cells. Frames are normalized (0…1);
    /// the renderer resolves them against `canvasSize`.
    public let textOverlays: [TextOverlay]
    /// Scales the overlays' reference-canvas point sizes to `canvasSize`
    /// (`canvasSize.height / referenceCanvas.height`). 1 for a full-res export.
    public let textFontScale: CGFloat
    /// Sticker overlays drawn (in order) above the text. Normalized center + size;
    /// resolution-independent SF Symbols, so no font scale is needed.
    public let stickerOverlays: [StickerOverlay]
    /// Bitmaps for personal (image-backed) stickers, keyed by `StickerOverlay.imageID`.
    /// Resolved by the caller so the renderer stays Sendable and off-actor.
    public let stickerImages: [UUID: CGImage]
    /// The pre-blurred backdrop a `.photoBlur` background draws. Resolved by the
    /// caller (the view model owns the photos), nil for every other background.
    public let backgroundPhoto: CGImage?
    /// Cell shadow and outline. Margin is already baked into the cell frames.
    public let frameStyle: FrameStyle

    public init(
        canvasSize: CGSize,
        background: CollageBackground,
        cells: [RenderCell],
        textOverlays: [TextOverlay] = [],
        textFontScale: CGFloat = 1,
        stickerOverlays: [StickerOverlay] = [],
        stickerImages: [UUID: CGImage] = [:],
        backgroundPhoto: CGImage? = nil,
        frameStyle: FrameStyle = FrameStyle()
    ) {
        self.canvasSize = canvasSize
        self.background = background
        self.cells = cells
        self.textOverlays = textOverlays
        self.textFontScale = textFontScale
        self.stickerOverlays = stickerOverlays
        self.stickerImages = stickerImages
        self.backgroundPhoto = backgroundPhoto
        self.frameStyle = frameStyle
    }
}

/// Composites a `RenderRequest` into a `CGImage`. `UIGraphicsImageRenderer` may
/// be used off the main thread, so exports run on a background queue.
public final class CollageRenderer: @unchecked Sendable {

    public init() {}

    /// Renders the request at the given pixel scale (1 canvas point = `scale` px).
    public func render(_ request: RenderRequest, scale: CGFloat) -> CGImage? {
        guard request.canvasSize.width > 0, request.canvasSize.height > 0 else { return nil }

        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: request.canvasSize, format: format)

        let output = renderer.image { rendererContext in
            let cg = rendererContext.cgContext

            // Canvas background (also shows through the gaps between cells).
            BackgroundRendering.draw(request.background, canvasSize: request.canvasSize,
                                     photo: request.backgroundPhoto, in: cg)

            let shortSide = min(request.canvasSize.width, request.canvasSize.height)
            let shadow = request.frameStyle.shadowGeometry(canvasShortSide: shortSide)
            let outlineWidth = CGFloat(request.frameStyle.outlineWidth)

            // One shadow for every cell, cast before any cell is drawn — the same
            // single shadow the canvas casts from one combined path. Shadowing each
            // cell as it is drawn would darken neighbours already painted.
            //
            // Reference-point geometry, NOT multiplied by the raster scale: the
            // renderer's scale is part of the context's base space, which shadows
            // do follow. Measured — a 0.5× thumbnail and a 1× export match within
            // 4/255 this way, and scaling again halved the thumbnail's shadow
            // (`testAThumbnailCarriesTheSameShadowAsTheExport`).
            if let shadow {
                cg.saveGState()
                cg.setShadow(offset: shadow.offset, blur: shadow.blur,
                             color: UIColor.black.withAlphaComponent(shadow.opacity).cgColor)
                cg.beginTransparencyLayer(auxiliaryInfo: nil)
                cg.setFillColor(Theme.Color.cellWell.cgColor)
                for cell in request.cells where cell.frame.width > 0 && cell.frame.height > 0 {
                    cg.addPath(cell.clipShape.path(in: cell.frame, cornerRadius: cell.cornerRadius))
                }
                cg.fillPath()
                cg.endTransparencyLayer()
                cg.restoreGState()
            }

            for cell in request.cells where cell.frame.width > 0 && cell.frame.height > 0 {
                let cellPath = cell.clipShape.path(in: cell.frame, cornerRadius: cell.cornerRadius)

                cg.saveGState()

                // Clip to the cell's shape (rectangle / rounded-rect / polygon /
                // ellipse). The parametric shape regenerates the exact path the
                // live canvas mask used, so export matches the preview.
                if cell.clipShape.isRectangle, cell.cornerRadius <= 0 {
                    UIBezierPath(rect: cell.frame).addClip()
                } else {
                    cg.addPath(cell.clipShape.path(in: cell.frame, cornerRadius: cell.cornerRadius))
                    cg.clip()
                }

                if let cgImage = cell.image {
                    draw(image: UIImage(cgImage: cgImage), in: cell.frame, transform: cell.transform, context: cg)
                } else {
                    EmptyCellChrome.draw(
                        in: cell.frame,
                        shape: cell.clipShape,
                        cornerRadius: cell.cornerRadius,
                        canvasShortSide: min(request.canvasSize.width, request.canvasSize.height),
                        context: cg
                    )
                }

                // Inside the cell's clip, so a stroke twice the width leaves
                // exactly `outlineWidth` visible — the same inner-half trick the
                // canvas uses, which keeps polygon outlines exact without
                // offsetting their paths.
                if outlineWidth > 0 {
                    cg.addPath(cellPath)
                    cg.setStrokeColor(UIColor(hex: request.frameStyle.outlineHex).cgColor)
                    cg.setLineWidth(outlineWidth * 2)
                    cg.strokePath()
                }

                cg.restoreGState()
            }

            // Text zones composite on top of the photo cells, in authoring order.
            for overlay in request.textOverlays {
                TextRendering.draw(
                    overlay,
                    in: TextRendering.frame(for: overlay, in: request.canvasSize),
                    fontScale: request.textFontScale,
                    context: cg
                )
            }

            // Stickers composite above the text, in authoring order.
            for overlay in request.stickerOverlays {
                StickerRendering.draw(
                    overlay, in: request.canvasSize, context: cg,
                    source: overlay.imageID.flatMap { request.stickerImages[$0] })
            }
        }
        return output.cgImage
    }

    // MARK: - Cell drawing

    private func draw(image: UIImage, in cellFrame: CGRect, transform: CellTransform, context cg: CGContext) {
        let base = aspectFillRect(imageSize: image.size, in: cellFrame)
        let center = CGPoint(x: cellFrame.midX, y: cellFrame.midY)

        cg.saveGState()
        // Apply pan/rotate/zoom around the cell centre.
        cg.translateBy(x: center.x + CGFloat(transform.panX), y: center.y + CGFloat(transform.panY))
        cg.rotate(by: CGFloat(transform.rotationRadians))
        cg.scaleBy(x: CGFloat(transform.zoom), y: CGFloat(transform.zoom))
        cg.translateBy(x: -center.x, y: -center.y)
        image.draw(in: base)
        cg.restoreGState()
    }

    private func aspectFillRect(imageSize: CGSize, in frame: CGRect) -> CGRect {
        guard imageSize.width > 0, imageSize.height > 0 else { return frame }
        let scale = max(frame.width / imageSize.width, frame.height / imageSize.height)
        let width = imageSize.width * scale
        let height = imageSize.height * scale
        return CGRect(
            x: frame.midX - width / 2,
            y: frame.midY - height / 2,
            width: width,
            height: height
        )
    }
}
