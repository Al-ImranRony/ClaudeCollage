//
//  BackgroundRendering.swift
//  Caroullage
//
//  Draws a `CollageBackground` — the one painter both the live canvas (which
//  rasterizes it once per change into a layer) and `CollageRenderer` (export
//  and thumbnails) call, so a gradient or pattern in the editor is the same
//  gradient or pattern in the file.
//
//  Everything is drawn in REFERENCE-CANVAS points (a 1080-wide canvas), and the
//  caller scales the context. A pattern's tile size is a fraction of the canvas,
//  so a preview and a 4× export show the same number of dots.
//

import UIKit
import CoreImage

enum BackgroundRendering {

    /// Fills `canvasSize` (reference points, origin zero) in `context`.
    /// `photo` is the pre-blurred backdrop for `.photoBlur`; ignored otherwise.
    static func draw(_ background: CollageBackground, canvasSize: CGSize,
                     photo: CGImage?, in context: CGContext) {
        let rect = CGRect(origin: .zero, size: canvasSize)
        context.saveGState()
        defer { context.restoreGState() }

        // Always lay down the representative colour first: it is what shows if
        // anything below cannot be drawn (no photo yet, a malformed gradient).
        context.setFillColor(UIColor(hex: background.hex).cgColor)
        context.fill(rect)

        switch background {
        case .solid:
            break
        case let .gradient(colors, angle):
            drawGradient(colors: colors, angle: angle, in: rect, context: context)
        case let .pattern(kind, ink, paper):
            context.setFillColor(UIColor(hex: paper).cgColor)
            context.fill(rect)
            drawPattern(kind, ink: UIColor(hex: ink).cgColor, in: rect, context: context)
        case let .photoBlur(dim):
            guard let photo else { break }
            drawAspectFill(photo, in: rect, context: context)
            if dim > 0 {
                context.setFillColor(UIColor.black.withAlphaComponent(min(dim, 1)).cgColor)
                context.fill(rect)
            }
        }
    }

    /// The background rasterized at `scale` pixels per reference point — what the
    /// live canvas puts in its background layer. Nil for a solid colour, which
    /// the canvas paints as a plain `backgroundColor` instead.
    static func image(_ background: CollageBackground, canvasSize: CGSize,
                      scale: CGFloat, photo: CGImage?) -> CGImage? {
        guard !background.isSolid, canvasSize.width > 0, canvasSize.height > 0, scale > 0 else { return nil }
        let format = UIGraphicsImageRendererFormat()
        format.scale = scale
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: canvasSize, format: format)
        return renderer.image { ctx in
            draw(background, canvasSize: canvasSize, photo: photo, in: ctx.cgContext)
        }.cgImage
    }

    // MARK: - Photo blur backdrop

    /// The longest side the blurred backdrop is rendered at. A heavy blur has no
    /// detail to lose, so a small bitmap is indistinguishable from a large one —
    /// and it is cheap enough to build synchronously on a discrete edit.
    static let backdropMaxDimension: CGFloat = 360

    private static let ciContext = CIContext(options: [.useSoftwareRenderer: false])

    /// `source` cropped to `canvasSize`'s aspect, shrunk, and blurred heavily.
    static func blurredBackdrop(from source: CGImage, canvasSize: CGSize) -> CGImage? {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return nil }
        let input = CIImage(cgImage: source)
        let crop = aspectFillCrop(of: input.extent.size, to: canvasSize)
        let scale = backdropMaxDimension / max(crop.width, crop.height)
        let shrunk = input.cropped(to: crop)
            .transformed(by: CGAffineTransform(translationX: -crop.minX, y: -crop.minY))
            .transformed(by: CGAffineTransform(scaleX: min(scale, 1), y: min(scale, 1)))
        let extent = shrunk.extent.integral
        let blurred = shrunk.clampedToExtent()
            .applyingGaussianBlur(sigma: Double(max(extent.width, extent.height)) * 0.06)
            .cropped(to: extent)
        return ciContext.createCGImage(blurred, from: extent)
    }

    // MARK: - Private

    private static func aspectFillCrop(of size: CGSize, to target: CGSize) -> CGRect {
        let targetAspect = target.width / target.height
        if size.width / size.height > targetAspect {
            let width = size.height * targetAspect
            return CGRect(x: (size.width - width) / 2, y: 0, width: width, height: size.height)
        }
        let height = size.width / targetAspect
        return CGRect(x: 0, y: (size.height - height) / 2, width: size.width, height: height)
    }

    private static func drawAspectFill(_ image: CGImage, in rect: CGRect, context: CGContext) {
        let size = CGSize(width: image.width, height: image.height)
        let scale = max(rect.width / size.width, rect.height / size.height)
        let drawn = CGSize(width: size.width * scale, height: size.height * scale)
        let target = CGRect(x: rect.midX - drawn.width / 2, y: rect.midY - drawn.height / 2,
                            width: drawn.width, height: drawn.height)
        context.saveGState()
        context.clip(to: rect)
        // UIKit contexts are flipped relative to Core Graphics image space.
        context.translateBy(x: 0, y: target.maxY + target.minY)
        context.scaleBy(x: 1, y: -1)
        context.interpolationQuality = .high
        context.draw(image, in: target)
        context.restoreGState()
    }

    private static func drawGradient(colors: [String], angle: Double, in rect: CGRect, context: CGContext) {
        let cgColors = colors.map { UIColor(hex: $0).cgColor } as CFArray
        guard colors.count >= 2,
              let gradient = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: cgColors, locations: nil)
        else { return }
        // Direction in UIKit space (y down): 0° points down, 90° points right.
        let radians = angle * .pi / 180
        let direction = CGVector(dx: sin(radians), dy: cos(radians))
        // The projection of the rect onto the direction, so the end colours land
        // exactly on the far corners whatever the angle and aspect.
        let length = abs(rect.width * direction.dx) + abs(rect.height * direction.dy)
        let center = CGPoint(x: rect.midX, y: rect.midY)
        let start = CGPoint(x: center.x - direction.dx * length / 2, y: center.y - direction.dy * length / 2)
        let end = CGPoint(x: center.x + direction.dx * length / 2, y: center.y + direction.dy * length / 2)
        context.drawLinearGradient(gradient, start: start, end: end,
                                   options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    }

    /// Tiles the motif across `rect`. Tile size scales with the canvas's short
    /// side so the density is the same on a post, a story and a thumbnail.
    private static func drawPattern(_ kind: BackgroundPattern, ink: CGColor, in rect: CGRect, context: CGContext) {
        let tile = max(8, min(rect.width, rect.height) * 0.05)
        context.setFillColor(ink)
        context.setStrokeColor(ink)

        switch kind {
        case .dots:
            let radius = tile * 0.16
            forEachTile(rect, tile) { origin, row in
                // Offset alternate rows for the classic polka layout.
                let x = origin.x + tile / 2 + (row.isMultiple(of: 2) ? 0 : tile / 2)
                context.fillEllipse(in: CGRect(x: x - radius, y: origin.y + tile / 2 - radius,
                                               width: radius * 2, height: radius * 2))
            }
        case .grid:
            context.setLineWidth(max(1, tile * 0.04))
            var x = rect.minX
            while x <= rect.maxX { context.move(to: CGPoint(x: x, y: rect.minY)); context.addLine(to: CGPoint(x: x, y: rect.maxY)); x += tile }
            var y = rect.minY
            while y <= rect.maxY { context.move(to: CGPoint(x: rect.minX, y: y)); context.addLine(to: CGPoint(x: rect.maxX, y: y)); y += tile }
            context.strokePath()
        case .stripes:
            context.setLineWidth(tile * 0.35)
            let span = rect.width + rect.height
            var offset = -rect.height
            while offset <= span {
                context.move(to: CGPoint(x: rect.minX + offset, y: rect.maxY))
                context.addLine(to: CGPoint(x: rect.minX + offset + rect.height, y: rect.minY))
                offset += tile
            }
            context.strokePath()
        case .gingham:
            context.setAlpha(0.45)
            var x = rect.minX
            while x <= rect.maxX { context.fill(CGRect(x: x, y: rect.minY, width: tile / 2, height: rect.height)); x += tile }
            var y = rect.minY
            while y <= rect.maxY { context.fill(CGRect(x: rect.minX, y: y, width: rect.width, height: tile / 2)); y += tile }
            context.setAlpha(1)
        case .checker:
            forEachTile(rect, tile) { origin, row in
                let column = Int(((origin.x - rect.minX) / tile).rounded())
                if (row + column).isMultiple(of: 2) {
                    context.fill(CGRect(origin: origin, size: CGSize(width: tile, height: tile)))
                }
            }
        case .waves:
            context.setLineWidth(max(1, tile * 0.08))
            context.setLineCap(.round)
            var y = rect.minY + tile / 2
            while y <= rect.maxY + tile {
                context.move(to: CGPoint(x: rect.minX - tile, y: y))
                var x = rect.minX - tile
                while x <= rect.maxX + tile {
                    context.addQuadCurve(to: CGPoint(x: x + tile / 2, y: y),
                                         control: CGPoint(x: x + tile / 4, y: y - tile * 0.22))
                    context.addQuadCurve(to: CGPoint(x: x + tile, y: y),
                                         control: CGPoint(x: x + tile * 0.75, y: y + tile * 0.22))
                    x += tile
                }
                y += tile * 0.6
            }
            context.strokePath()
        case .hearts:
            let size = tile * 0.42
            forEachTile(rect, tile * 1.4) { origin, row in
                let x = origin.x + tile * 0.7 + (row.isMultiple(of: 2) ? 0 : tile * 0.7)
                context.addPath(heartPath(center: CGPoint(x: x, y: origin.y + tile * 0.7), size: size))
            }
            context.fillPath()
        }
    }

    private static func forEachTile(_ rect: CGRect, _ tile: CGFloat, _ body: (CGPoint, Int) -> Void) {
        var row = 0
        var y = rect.minY - tile
        while y <= rect.maxY {
            var x = rect.minX - tile
            while x <= rect.maxX {
                body(CGPoint(x: x, y: y), row)
                x += tile
            }
            y += tile
            row += 1
        }
    }

    private static func heartPath(center: CGPoint, size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let top = CGPoint(x: center.x, y: center.y - size * 0.25)
        path.move(to: CGPoint(x: center.x, y: center.y + size * 0.5))
        path.addCurve(to: CGPoint(x: center.x - size * 0.5, y: top.y),
                      control1: CGPoint(x: center.x - size * 0.2, y: center.y + size * 0.3),
                      control2: CGPoint(x: center.x - size * 0.5, y: center.y + size * 0.1))
        path.addArc(center: CGPoint(x: center.x - size * 0.25, y: top.y), radius: size * 0.25,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        path.addArc(center: CGPoint(x: center.x + size * 0.25, y: top.y), radius: size * 0.25,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        path.addCurve(to: CGPoint(x: center.x, y: center.y + size * 0.5),
                      control1: CGPoint(x: center.x + size * 0.5, y: center.y + size * 0.1),
                      control2: CGPoint(x: center.x + size * 0.2, y: center.y + size * 0.3))
        path.closeSubpath()
        return path
    }
}
