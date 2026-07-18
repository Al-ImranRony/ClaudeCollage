//
//  SafeZoneOverlayView.swift
//  ClaudeCollage
//
//  Step 03b slice 6 (refined for QA) — dims the regions a platform's UI would cover,
//  drawn over a preview frame. Fills the same rect as the frame image, so the
//  projected regions map straight to pixels.
//
//  Presentation: a strong solid dim + a crisp bracket that traces only the edges
//  facing the safe area (edges sitting on the frame border are skipped, so a zone
//  reads as a bracket anchored to that border rather than a floating box) + a label
//  naming the UI that sits there. That removes the "why is there a random rectangle"
//  ambiguity. Preview-only — never exported.
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

        let zones = preset.coveredZones(forFrameAspect: bounds.width / bounds.height)
        let edge: CGFloat = 0.5

        // 1) Strong dim so each zone clearly reads as "keep content out".
        ctx.setFillColor(UIColor.black.withAlphaComponent(0.60).cgColor)
        for zone in zones { ctx.fill(pixelRect(zone.rect)) }

        // 2) Bracket: stroke only the edges NOT sitting on the frame border, so the
        //    zone looks anchored to that border instead of a floating box.
        ctx.setStrokeColor(UIColor.white.withAlphaComponent(0.85).cgColor)
        ctx.setLineWidth(1.5)
        for zone in zones {
            let r = pixelRect(zone.rect)
            if r.minY > edge { ctx.move(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.minY)) }
            if r.maxY < bounds.height - edge { ctx.move(to: CGPoint(x: r.minX, y: r.maxY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
            if r.minX > edge { ctx.move(to: CGPoint(x: r.minX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.minX, y: r.maxY)) }
            if r.maxX < bounds.width - edge { ctx.move(to: CGPoint(x: r.maxX, y: r.minY)); ctx.addLine(to: CGPoint(x: r.maxX, y: r.maxY)) }
        }
        ctx.strokePath()

        // 3) Label each zone (when it fits) so the region is self-explanatory.
        let fontSize = max(9, min(15, bounds.width * 0.03))
        let attributes: [NSAttributedString.Key: Any] = [
            .font: UIFont.systemFont(ofSize: fontSize, weight: .semibold),
            .foregroundColor: UIColor.white.withAlphaComponent(0.92),
        ]
        for zone in zones {
            let r = pixelRect(zone.rect)
            let text = zone.label as NSString
            let size = text.size(withAttributes: attributes)
            guard r.width > size.width + 8, r.height > size.height + 6 else { continue }
            text.draw(at: CGPoint(x: r.midX - size.width / 2, y: r.midY - size.height / 2),
                      withAttributes: attributes)
        }
    }

    private func pixelRect(_ normalized: CGRect) -> CGRect {
        CGRect(x: normalized.minX * bounds.width, y: normalized.minY * bounds.height,
               width: normalized.width * bounds.width, height: normalized.height * bounds.height)
    }
}
