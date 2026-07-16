//
//  CollageRenderer.swift
//  ClaudeCollage
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

    public init(
        canvasSize: CGSize,
        background: CollageBackground,
        cells: [RenderCell],
        textOverlays: [TextOverlay] = [],
        textFontScale: CGFloat = 1
    ) {
        self.canvasSize = canvasSize
        self.background = background
        self.cells = cells
        self.textOverlays = textOverlays
        self.textFontScale = textFontScale
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
            UIColor(background: request.background).setFill()
            cg.fill(CGRect(origin: .zero, size: request.canvasSize))

            for cell in request.cells where cell.frame.width > 0 && cell.frame.height > 0 {
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
                    drawEmptyPlaceholder(in: cell.frame, context: cg)
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

    private func drawEmptyPlaceholder(in frame: CGRect, context cg: CGContext) {
        UIColor.secondarySystemBackground.setFill()
        cg.fill(frame)

        let side = min(frame.width, frame.height) * 0.16
        let center = CGPoint(x: frame.midX, y: frame.midY)
        let line = UIBezierPath()
        line.lineWidth = max(1, side * 0.10)
        line.move(to: CGPoint(x: center.x - side / 2, y: center.y))
        line.addLine(to: CGPoint(x: center.x + side / 2, y: center.y))
        line.move(to: CGPoint(x: center.x, y: center.y - side / 2))
        line.addLine(to: CGPoint(x: center.x, y: center.y + side / 2))
        UIColor.tertiaryLabel.setStroke()
        line.stroke()
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
