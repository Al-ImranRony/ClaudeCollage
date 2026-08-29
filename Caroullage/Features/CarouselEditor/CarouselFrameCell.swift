//
//  CarouselFrameCell.swift
//  Caroullage
//
//  One panel of the carousel strip.
//
//  Step 06 turned the navigator from a 2-column grid of separate cards into one
//  continuous canvas, which changes what a cell is: panels touch, only the strip's
//  two ends are rounded, and the join between neighbours is a hairline rather than
//  a gutter. A cell therefore no longer owns its corner rounding — the strip tells
//  it which corners it is on.
//
//  The number badge was a caption on a 90%-opaque accent rectangle, sized by
//  padding its string with literal spaces. It is now a material capsule with
//  monospaced digits: material so it holds up over a bright photo and over an
//  empty frame alike, monospaced so the badge does not resize between frame 9 and
//  frame 10, and accent-filled only on the selected panel so selection reads
//  without needing a second affordance.
//

import UIKit

final class CarouselFrameCell: UICollectionViewCell {

    static let reuseID = "CarouselFrameCell"

    /// Which neighbour edge, if any, this panel draws its seam on.
    enum Seam {
        case none, trailing, bottom
    }

    private let imageView = UIImageView()
    private let badge = UIVisualEffectView(effect: UIBlurEffect(style: .systemThinMaterialDark))
    private let numberLabel = UILabel()

    // Two fixed hairlines rather than one that is re-constrained per configure:
    // a cell is reused constantly and `configure` runs before it has been laid
    // out, so deriving a line's length from `bounds` gets it wrong on first use.
    private let trailingSeam = UIView()
    private let bottomSeam = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = Theme.Color.surface
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true
        contentView.layer.borderColor = Theme.Color.accent.cgColor

        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.backgroundColor = Theme.Color.controlFill
        imageView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(imageView)

        for seam in [trailingSeam, bottomSeam] {
            seam.backgroundColor = Theme.Color.separator
            seam.isHidden = true
            seam.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(seam)
        }

        numberLabel.font = .monospacedDigitSystemFont(ofSize: 13, weight: .semibold)
        numberLabel.textColor = .white
        numberLabel.textAlignment = .center
        numberLabel.translatesAutoresizingMaskIntoConstraints = false

        badge.layer.cornerRadius = 11
        badge.layer.cornerCurve = .continuous
        badge.clipsToBounds = true
        badge.translatesAutoresizingMaskIntoConstraints = false
        badge.contentView.addSubview(numberLabel)
        contentView.addSubview(badge)

        let hairline = CarouselStripLayout.seamWidth

        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: contentView.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            // Drawn inside the panel, so neighbouring panels still meet exactly.
            trailingSeam.topAnchor.constraint(equalTo: contentView.topAnchor),
            trailingSeam.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            trailingSeam.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            trailingSeam.widthAnchor.constraint(equalToConstant: hairline),

            bottomSeam.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            bottomSeam.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            bottomSeam.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            bottomSeam.heightAnchor.constraint(equalToConstant: hairline),

            badge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 8),
            badge.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 8),
            badge.heightAnchor.constraint(equalToConstant: 22),
            badge.widthAnchor.constraint(greaterThanOrEqualToConstant: 22),

            numberLabel.centerYAnchor.constraint(equalTo: badge.contentView.centerYAnchor),
            numberLabel.leadingAnchor.constraint(
                equalTo: badge.contentView.leadingAnchor, constant: 7),
            numberLabel.trailingAnchor.constraint(
                equalTo: badge.contentView.trailingAnchor, constant: -7),
        ])

        observeAppearance()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func prepareForReuse() {
        super.prepareForReuse()
        imageView.image = nil
        contentView.layer.borderWidth = 0
        trailingSeam.isHidden = true
        bottomSeam.isHidden = true
    }

    /// Re-resolves the accent CGColor, which does not follow a light/dark change
    /// on its own — CGColors are static once resolved.
    private func observeAppearance() {
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: Self, _) in
            cell.contentView.layer.borderColor = Theme.Color.accent.cgColor
        }
    }

    /// The rounded shape this panel presents — the context menu needs the same
    /// path, or it lifts the cell onto a square platter that shows at the corners.
    var visiblePath: UIBezierPath {
        guard contentView.layer.cornerRadius > 0 else {
            return UIBezierPath(rect: bounds)
        }
        return UIBezierPath(
            roundedRect: bounds,
            byRoundingCorners: Self.rectCorners(from: contentView.layer.maskedCorners),
            cornerRadii: CGSize(width: contentView.layer.cornerRadius,
                                height: contentView.layer.cornerRadius))
    }

    private static func rectCorners(from mask: CACornerMask) -> UIRectCorner {
        var corners: UIRectCorner = []
        if mask.contains(.layerMinXMinYCorner) { corners.insert(.topLeft) }
        if mask.contains(.layerMaxXMinYCorner) { corners.insert(.topRight) }
        if mask.contains(.layerMinXMaxYCorner) { corners.insert(.bottomLeft) }
        if mask.contains(.layerMaxXMaxYCorner) { corners.insert(.bottomRight) }
        return corners
    }

    func configure(
        number: Int,
        image: UIImage?,
        isSelected: Bool,
        corners: CACornerMask,
        seam: Seam
    ) {
        imageView.image = image
        numberLabel.text = "\(number)"

        contentView.layer.maskedCorners = corners
        contentView.layer.cornerRadius = corners.isEmpty ? 0 : CarouselStripLayout.cornerRadius
        contentView.layer.borderWidth = isSelected ? 2 : 0

        // Selected: the accent fill. Otherwise the material, which stays readable
        // over a photograph of any brightness.
        badge.contentView.backgroundColor = isSelected ? Theme.Color.accentStrong : .clear
        numberLabel.textColor = isSelected ? Theme.Color.textOnAccent : .white

        trailingSeam.isHidden = seam != .trailing
        bottomSeam.isHidden = seam != .bottom

        isAccessibilityElement = true
        accessibilityLabel = "Frame \(number)"
        accessibilityTraits = isSelected ? [.button, .selected] : .button
    }
}
