//
//  SafeZoneOverlayView.swift
//  ClaudeCollage
//
//  Step 03b slice 6 — dims the regions a platform's UI would cover, drawn over a
//  preview frame. Fills the same rect as the frame image (its superview sizes it to
//  the frame), so the normalized regions map straight to pixels. Preview-only.
//

import UIKit

final class SafeZoneOverlayView: UIView {

    var preset: SafeZonePreset = .none {
        didSet { setNeedsDisplay() }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        isUserInteractionEnabled = false
        isOpaque = false
        // Reproject on every bounds change — the regions depend on the frame aspect.
        contentMode = .redraw
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func draw(_ rect: CGRect) {
        guard preset != .none, bounds.width > 0, bounds.height > 0,
              let ctx = UIGraphicsGetCurrentContext() else { return }

        // Project the platform's 9:16 chrome onto this frame's actual aspect.
        let regions = preset.coveredRegions(forFrameAspect: bounds.width / bounds.height)
        let pixelRects = regions.map { region in
            CGRect(x: region.minX * bounds.width, y: region.minY * bounds.height,
                   width: region.width * bounds.width, height: region.height * bounds.height)
        }

        // Strong dim so it reads clearly as "keep content out".
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.66).cgColor)
        for rect in pixelRects { ctx.fill(rect) }

        // A light dashed edge delineates each zone against the photo underneath.
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.6).cgColor)
        ctx.setLineWidth(1)
        ctx.setLineDash(phase: 0, lengths: [5, 4])
        for rect in pixelRects { ctx.stroke(rect.insetBy(dx: 0.5, dy: 0.5)) }
    }
}
