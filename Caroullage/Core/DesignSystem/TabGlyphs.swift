//
//  TabGlyphs.swift
//  Caroullage
//
//  The Home and Collage tab glyphs, drawn rather than borrowed.
//
//  SF Symbols' `house` and `rectangle.3.group` are what every app has, and
//  the second one does not even say "collage": it is three loose cards, the
//  same idea the Carousel tab's `rectangle.stack` already owns. These two are
//  this app's own, drawn on the same grid so they read as a set:
//
//    • Home is a soft-shouldered house with an arched door and a four-point
//      spark over the eave — the tab is "made for you" (suggestions, fresh
//      templates), not a settings landing page. Outline when away, solid with
//      the door cut out when you are there.
//    • Collage is a single framed layout split asymmetrically — one tall cell
//      and two stacked ones of unequal height, because no real collage is a
//      uniform grid (that is Projects' 2×2). The tall cell carries a sun and
//      a ridge cut through it, so the glyph is a layout *of photos*, not a
//      spreadsheet. Always solid, like the tabs beside it.
//
//  Construction rules, so a future glyph can join the set:
//    • 26×26pt canvas, live area 2…24 — the HIG's 25pt tab glyph with the
//      optical overshoot pointed shapes need.
//    • One stroke weight, 2pt, with round caps and joins. That matches SF's
//      regular weight at tab size, so the custom glyphs sit beside the system
//      ones without looking heavier or lighter.
//    • Solid shapes are filled AND stroked at the same weight. Round joins
//      only soften a stroke, so filling alone would leave the solid state with
//      sharper corners than its outline — this keeps both states one shape.
//    • Knock-outs are cleared with the same stroke, so a 1pt cut still reads
//      at @2x instead of disappearing into anti-aliasing.
//
//  Everything below is plain CoreGraphics (the UIKit wrapper is at the bottom)
//  so the paths can be rendered on a Mac for review without a simulator.
//

import CoreGraphics

enum TabGlyph {
    case home
    case collage

    /// Point size of the canvas every glyph is drawn on.
    static let canvas = CGSize(width: 26, height: 26)
    static let lineWidth: CGFloat = 2.0

    /// Draws the glyph in `ctx`, in canvas points with a top-left origin.
    /// The caller sets the fill/stroke colour; knock-outs use `.clear`.
    func draw(in ctx: CGContext, filled: Bool) {
        ctx.setLineWidth(Self.lineWidth)
        ctx.setLineCap(.round)
        ctx.setLineJoin(.round)
        switch self {
        case .home: drawHome(in: ctx, filled: filled)
        case .collage: drawCollage(in: ctx)
        }
    }

    // MARK: - Home

    private func drawHome(in ctx: CGContext, filled: Bool) {
        // Walls 5…19.5 wide, eaves at y 11.5, apex at 3.4. The roof pitch
        // (≈ 40°) is shallower than SF's house — friendlier, less "warning".
        let body = CGMutablePath()
        body.move(to: CGPoint(x: 3.6, y: 11.8))
        body.addLine(to: CGPoint(x: 12.2, y: 4.2))
        body.addLine(to: CGPoint(x: 20.8, y: 11.8))
        body.addLine(to: CGPoint(x: 20.8, y: 19.6))
        body.addArc(tangent1End: CGPoint(x: 20.8, y: 22.4), tangent2End: CGPoint(x: 18, y: 22.4), radius: 2.6)
        body.addLine(to: CGPoint(x: 6.4, y: 22.4))
        body.addArc(tangent1End: CGPoint(x: 3.6, y: 22.4), tangent2End: CGPoint(x: 3.6, y: 19.6), radius: 2.6)
        body.closeSubpath()

        // Arched door, centred on the walls, its sill on the floor line.
        let doorCenterX: CGFloat = 12.2
        let doorHalf: CGFloat = 2.5
        let door = CGMutablePath()
        door.move(to: CGPoint(x: doorCenterX - doorHalf, y: 22.4))
        door.addLine(to: CGPoint(x: doorCenterX - doorHalf, y: 17.6))
        door.addArc(center: CGPoint(x: doorCenterX, y: 17.6), radius: doorHalf,
                    startAngle: .pi, endAngle: 0, clockwise: false)
        door.addLine(to: CGPoint(x: doorCenterX + doorHalf, y: 22.4))

        if filled {
            ctx.addPath(body); ctx.fillPath()
            ctx.addPath(body); ctx.strokePath()
            // The door is a closed arch cut from the solid, its sill raised a
            // stroke's width off the floor so the house keeps a clean base
            // line instead of a notch with slivers either side of it.
            let cut = CGMutablePath()
            cut.move(to: CGPoint(x: doorCenterX - doorHalf + 0.3, y: 21.0))
            cut.addLine(to: CGPoint(x: doorCenterX - doorHalf + 0.3, y: 17.6))
            cut.addArc(center: CGPoint(x: doorCenterX, y: 17.6), radius: doorHalf - 0.3,
                       startAngle: .pi, endAngle: 0, clockwise: false)
            cut.addLine(to: CGPoint(x: doorCenterX + doorHalf - 0.3, y: 21.0))
            cut.closeSubpath()
            ctx.setBlendMode(.clear)
            ctx.addPath(cut); ctx.fillPath()
            ctx.setBlendMode(.normal)
        } else {
            ctx.addPath(body); ctx.strokePath()
            ctx.addPath(door); ctx.strokePath()
        }

        // The spark: a four-point star with concave sides, always solid — at
        // this size an outlined star is just noise. It sits in the corner the
        // roof leaves empty, clear of the slope by a full stroke.
        ctx.addPath(Self.spark(center: CGPoint(x: 21.4, y: 4.4), radius: 3.1))
        ctx.fillPath()
    }

    /// Four-point star whose sides curve inward through the centre — the
    /// "sparkle" shape, not a plus.
    private static func spark(center c: CGPoint, radius r: CGFloat) -> CGPath {
        let p = CGMutablePath()
        let pinch: CGFloat = 0.18   // how far the waist sits from the centre
        p.move(to: CGPoint(x: c.x, y: c.y - r))
        p.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + r * pinch, y: c.y - r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + r * pinch, y: c.y + r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - r * pinch, y: c.y + r * pinch))
        p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - r * pinch, y: c.y - r * pinch))
        p.closeSubpath()
        return p
    }

    // MARK: - Collage

    private func drawCollage(in ctx: CGContext) {
        // Frame 3.2…22.8 × 3.8…22.2. Outer corners take the frame's radius, inner
        // ones a tight radius, so the three cells read as one cut sheet rather
        // than three cards — which is the Carousel glyph's job.
        let gutter: CGFloat = 1.9
        let outer: CGFloat = 2.4
        let inner: CGFloat = 0.3
        let minX: CGFloat = 3.2, maxX: CGFloat = 22.8
        let minY: CGFloat = 3.8, maxY: CGFloat = 22.2
        let split: CGFloat = 13.8      // tall cell takes ~52% — asymmetry on purpose
        let rowSplit: CGFloat = 10.6   // top-right cell is the shorter of the two

        let tall = CGRect(x: minX, y: minY, width: split - gutter / 2 - minX, height: maxY - minY)
        let topRight = CGRect(x: split + gutter / 2, y: minY,
                              width: maxX - split - gutter / 2, height: rowSplit - gutter / 2 - minY)
        let bottomRight = CGRect(x: split + gutter / 2, y: rowSplit + gutter / 2,
                                 width: maxX - split - gutter / 2, height: maxY - rowSplit - gutter / 2)

        // Inset by half a stroke so filled+stroked cells land exactly on the
        // frame edges and the gutters stay at their nominal width.
        let h = Self.lineWidth / 2
        let cells = [
            Self.cell(tall.insetBy(dx: h, dy: h), tl: outer, tr: inner, br: inner, bl: outer),
            Self.cell(topRight.insetBy(dx: h, dy: h), tl: inner, tr: outer, br: inner, bl: inner),
            Self.cell(bottomRight.insetBy(dx: h, dy: h), tl: inner, tr: inner, br: outer, bl: inner),
        ]
        for cell in cells {
            ctx.addPath(cell); ctx.fillPath()
            ctx.addPath(cell); ctx.strokePath()
        }

        // The photo in the tall cell: a sun and a two-peak ridge, cut out.
        ctx.setBlendMode(.clear)
        ctx.addEllipse(in: CGRect(x: 8.0, y: 7.4, width: 2.8, height: 2.8))
        ctx.fillPath()
        let ridge = CGMutablePath()
        ridge.move(to: CGPoint(x: 3.9, y: 18.4))
        ridge.addLine(to: CGPoint(x: 6.6, y: 14.6))
        ridge.addLine(to: CGPoint(x: 8.6, y: 17.0))
        ridge.addLine(to: CGPoint(x: 9.6, y: 15.8))
        ridge.addLine(to: CGPoint(x: 12.0, y: 18.8))
        ctx.setLineWidth(1.3)
        ctx.addPath(ridge); ctx.strokePath()
        ctx.setLineWidth(Self.lineWidth)
        ctx.setBlendMode(.normal)
    }

    /// Rounded rect with an independent radius per corner (top-left origin).
    private static func cell(_ r: CGRect, tl: CGFloat, tr: CGFloat, br: CGFloat, bl: CGFloat) -> CGPath {
        let p = CGMutablePath()
        p.move(to: CGPoint(x: r.minX + tl, y: r.minY))
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.maxY), radius: tr)
        p.addArc(tangent1End: CGPoint(x: r.maxX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.maxY), radius: br)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.maxY), tangent2End: CGPoint(x: r.minX, y: r.minY), radius: bl)
        p.addArc(tangent1End: CGPoint(x: r.minX, y: r.minY), tangent2End: CGPoint(x: r.maxX, y: r.minY), radius: tl)
        p.closeSubpath()
        return p
    }
}

#if canImport(UIKit)
import UIKit

extension TabGlyph {
    /// Point size of the rendered tab image (the canvas is scaled into it).
    static let renderedSide: CGFloat = 30

    /// A template image of the glyph, so the tab bar tints it like a symbol.
    /// `scale` multiplies the canvas — the large-content viewer (long-press a
    /// tab at accessibility text sizes) wants a bigger rendition, not an
    /// upscaled bitmap.
    func image(filled: Bool, scale: CGFloat = 1) -> UIImage {
        // The iOS 26 tab bar draws its symbols larger than the HIG's 25pt —
        // `square.grid.2x2.fill` comes out 21pt tall — so the 26pt design grid
        // is rendered into 30pt. Measured on device screenshots: at 26pt the
        // Collage glyph stood 18pt tall beside Projects' 21 and read as a
        // smaller, lesser tab.
        let side = Self.renderedSide * scale
        let image = UIGraphicsImageRenderer(size: CGSize(width: side, height: side)).image { renderer in
            let ctx = renderer.cgContext
            let zoom = side / Self.canvas.width
            ctx.scaleBy(x: zoom, y: zoom)
            ctx.setFillColor(UIColor.black.cgColor)
            ctx.setStrokeColor(UIColor.black.cgColor)
            draw(in: ctx, filled: filled)
        }
        return image.withRenderingMode(.alwaysTemplate)
    }
}
#endif
