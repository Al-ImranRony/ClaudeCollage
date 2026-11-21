//
//  CollageSpotlightCell.swift
//  Caroullage
//
//  2026-11-21 — the large paged card at the top of the Collage tab.
//
//  A browse card shows the artwork edge to edge, because in a grid you are
//  comparing. The spotlight has a different job — it is the one card on the
//  screen meant to make you want something — so it presents the template the
//  way a print is presented: whole, at its true proportions, lying on a softly
//  tinted stage with a shadow under it. The stage takes a wash of the
//  template's own background colour, so an instant print sits on cream and a
//  film roll on charcoal, and the row of cards reads as a set of different
//  objects rather than one rectangle repeated.
//
//  Cost: the shadow is a `shadowPath` (no offscreen pass) and the wash is one
//  gradient layer. The print's frame is computed in `layoutSubviews` from the
//  template's ratio, so it is right before the preview lands.
//

import UIKit

final class CollageSpotlightCell: UICollectionViewCell {

    struct Content {
        let name: String
        /// "Instant · 3 photos" — the category and the ask.
        let detail: String
        /// Width ÷ height of the template's canvas.
        let aspectRatio: CGFloat
        /// The template's background colour; tints the stage.
        let tintHex: String
        let tag: String?
        let locked: Bool
        let identifier: String
    }

    /// Room under the stage for the name and the detail line, grown with the
    /// text size so a large Dynamic Type name takes room from the stage's
    /// layout rather than drawing over the print. The layout and the cell ask
    /// the same function, so the two always agree.
    static func captionHeight(for traits: UITraitCollection) -> CGFloat {
        UIFontMetrics.default.scaledValue(for: 54, compatibleWith: traits).rounded()
    }

    private let stage = UIView()
    private let wash = CAGradientLayer()
    private let printShadow = UIView()
    private let printView = UIImageView()
    private let tagLabel = TagPillLabel()
    private let lockBadge = UIImageView()
    private let nameLabel = UILabel()
    private let detailLabel = UILabel()

    private var aspectRatio: CGFloat = 1
    private var tintHex = "#FFFFFF"
    private var previewTask: Task<Void, Never>?

    override init(frame: CGRect) {
        super.init(frame: frame)

        stage.backgroundColor = Theme.Color.artworkMat
        stage.layer.cornerRadius = Theme.Radius.xl
        stage.layer.cornerCurve = .continuous
        stage.clipsToBounds = true
        stage.layer.addSublayer(wash)
        wash.startPoint = CGPoint(x: 0.5, y: 0)
        wash.endPoint = CGPoint(x: 0.5, y: 1)

        printShadow.layer.shadowColor = UIColor.black.cgColor
        printShadow.layer.shadowOpacity = 0.22
        printShadow.layer.shadowRadius = 14
        printShadow.layer.shadowOffset = CGSize(width: 0, height: 8)

        printView.contentMode = .scaleAspectFill
        printView.clipsToBounds = true
        printView.layer.cornerRadius = 6
        printView.layer.cornerCurve = .continuous
        printView.backgroundColor = Theme.Color.cellWell

        lockBadge.contentMode = .center
        lockBadge.tintColor = Theme.Color.textOnAccent
        lockBadge.backgroundColor = Theme.Color.accentStrong
        lockBadge.layer.cornerRadius = 13
        lockBadge.clipsToBounds = true
        lockBadge.image = UIImage(
            systemName: "lock.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 12, weight: .semibold))
        lockBadge.isHidden = true

        nameLabel.font = Theme.Typography.headline
        nameLabel.textColor = Theme.Color.textPrimary
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.lineBreakMode = .byTruncatingTail

        detailLabel.font = Theme.Typography.caption
        detailLabel.textColor = Theme.Color.textSecondary
        detailLabel.adjustsFontForContentSizeCategory = true
        detailLabel.lineBreakMode = .byTruncatingTail

        contentView.addSubview(stage)
        stage.addSubview(printShadow)
        printShadow.addSubview(printView)
        for view in [tagLabel, lockBadge, nameLabel, detailLabel] {
            view.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(view)
        }
        NSLayoutConstraint.activate([
            tagLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.sm),
            tagLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.sm),
            lockBadge.topAnchor.constraint(equalTo: contentView.topAnchor, constant: Theme.Spacing.sm),
            lockBadge.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.sm),
            lockBadge.widthAnchor.constraint(equalToConstant: 26),
            lockBadge.heightAnchor.constraint(equalToConstant: 26),

            detailLabel.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -2),
            detailLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: Theme.Spacing.xxs),
            detailLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.xxs),
            nameLabel.bottomAnchor.constraint(equalTo: detailLabel.topAnchor, constant: -1),
            nameLabel.leadingAnchor.constraint(equalTo: detailLabel.leadingAnchor),
            nameLabel.trailingAnchor.constraint(equalTo: detailLabel.trailingAnchor),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (cell: Self, _) in
            cell.applyWash()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            // On the content, not the cell: the section's depth effect owns
            // the cell's transform, and resetting it to identity on release
            // would pop a peeking card to full size.
            contentView.setPressed(isHighlighted, scale: 0.97)
        }
    }

    func configure(_ content: Content, artwork: BrowseTemplateCell.Artwork) {
        nameLabel.text = content.name
        detailLabel.text = content.detail
        aspectRatio = max(0.3, min(content.aspectRatio, 3))
        tintHex = content.tintHex
        tagLabel.setTitle(content.tag)
        lockBadge.isHidden = !content.locked
        applyWash()
        setNeedsLayout()

        accessibilityIdentifier = content.identifier
        accessibilityLabel = content.name
        var spoken = [content.detail]
        if let tag = content.tag { spoken.insert(tag, at: 0) }
        if content.locked { spoken.append(String(localized: "premium")) }
        accessibilityValue = spoken.joined(separator: ", ")

        previewTask?.cancel()
        previewTask = nil
        if let image = artwork.cached {
            printView.image = UIImage(cgImage: image)
            return
        }
        printView.image = nil
        previewTask = Task { @MainActor [weak self] in
            let image = await artwork.load()
            guard !Task.isCancelled, let self, let image else { return }
            UIView.transition(
                with: self.printView, duration: Theme.Motion.duration(Theme.Motion.quick),
                options: [.transitionCrossDissolve, .allowUserInteraction]
            ) { self.printView.image = UIImage(cgImage: image) }
        }
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let stageFrame = CGRect(x: 0, y: 0, width: contentView.bounds.width,
                                height: max(0, contentView.bounds.height
                                    - Self.captionHeight(for: traitCollection)))
        stage.frame = stageFrame
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        wash.frame = stage.bounds
        CATransaction.commit()

        // The print fills the stage minus a mat, at its own proportions.
        let mat = stageFrame.insetBy(dx: stageFrame.width * 0.1, dy: stageFrame.height * 0.09)
        var size = CGSize(width: mat.width, height: mat.width / aspectRatio)
        if size.height > mat.height {
            size = CGSize(width: mat.height * aspectRatio, height: mat.height)
        }
        let printFrame = CGRect(x: stageFrame.midX - size.width / 2, y: stageFrame.midY - size.height / 2,
                                width: size.width, height: size.height).integral
        printShadow.frame = printFrame
        printView.frame = printShadow.bounds
        printShadow.layer.shadowPath = UIBezierPath(
            roundedRect: printShadow.bounds, cornerRadius: printView.layer.cornerRadius).cgPath
    }

    /// The stage takes a wash of the template's own ground colour, strongest at
    /// the top, over the neutral mat — so it works in both appearances.
    private func applyWash() {
        let tint = UIColor(hex: tintHex)
        let dark = traitCollection.userInterfaceStyle == .dark
        wash.colors = [tint.withAlphaComponent(dark ? 0.24 : 0.7).cgColor,
                       tint.withAlphaComponent(dark ? 0.06 : 0.22).cgColor]
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        previewTask?.cancel()
        previewTask = nil
        printView.image = nil
        tagLabel.setTitle(nil)
        lockBadge.isHidden = true
        accessibilityValue = nil
    }
}
