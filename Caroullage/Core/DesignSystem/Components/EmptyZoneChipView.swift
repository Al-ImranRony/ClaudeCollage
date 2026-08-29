//
//  EmptyZoneChipView.swift
//  Caroullage
//
//  Step 06 (visual) — the "+" chip, as a standalone view.
//
//  The photo canvas draws its own chip into `CellContentView`'s layer tree, where
//  it also owns the zone outline. Surfaces that already draw their own zone chrome
//  — the video editor, whose slots carry a real border and selection outline — only
//  need the affordance, and get it from here so both editors show the user the same
//  thing in the same place.
//

import UIKit

/// A filled disc with a "+" in it, centred in the view's bounds. Non-interactive:
/// the surface that hosts it owns the tap.
final class EmptyZoneChipView: UIView {

    private let chipLayer = CAShapeLayer()
    private let plusLayer = CAShapeLayer()

    /// The canvas's short side in on-screen points. The chip is capped against it
    /// so a full-bleed slot doesn't get an oversized disc.
    var canvasShortSide: CGFloat = 0 {
        didSet { if canvasShortSide != oldValue { setNeedsLayout() } }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        backgroundColor = .clear

        chipLayer.fillColor = Theme.Color.cellWellChip.cgColor
        layer.addSublayer(chipLayer)

        plusLayer.fillColor = UIColor.clear.cgColor
        plusLayer.strokeColor = Theme.Color.cellWellChipInk.cgColor
        plusLayer.lineCap = .round
        layer.addSublayer(plusLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, bounds.height > 0 else { return }
        let reference = canvasShortSide > 0 ? canvasShortSide : min(bounds.width, bounds.height)

        CATransaction.begin()
        CATransaction.setDisableActions(true)

        let (center, diameter) = EmptyCellChrome.chipPlacement(
            shape: .rectangle, frame: bounds, canvasShortSide: reference)
        chipLayer.frame = bounds
        chipLayer.path = CGPath(
            ellipseIn: CGRect(x: center.x - diameter / 2, y: center.y - diameter / 2,
                              width: diameter, height: diameter),
            transform: nil)
        plusLayer.frame = bounds
        plusLayer.lineWidth = EmptyCellChrome.plusLineWidth(chipDiameter: diameter)
        plusLayer.path = EmptyCellChrome.plusPath(center: center, chipDiameter: diameter)

        CATransaction.commit()
    }
}
