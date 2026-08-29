//
//  ShowcaseVideoCell.swift
//  Caroullage
//
//  Step 07 — the Video Collages strip's card, and the hero card whenever the
//  rotation lands on a video.
//
//  A sibling of `ShowcaseTemplateCell` rather than a subclass of it (that cell is
//  `final`, and deliberately: it renders a still through `CollageRenderer` and
//  nothing else). The two share the parts that matter — `ShowcaseScrimView`, the
//  caption treatment, the press spring — so the strips still read as one family.
//  Same reasoning as `ShowcaseTemplateCell`'s own header: nothing here is generic
//  enough to belong to one screen — the three strips and the hero card are all
//  the same card at different sizes — so it lives in the design system rather
//  than inside HomeViewController.
//
//  A still frame cannot sell a video collage: the motion IS the product. The
//  poster is up instantly and is the FINAL state whenever motion is not allowed
//  (Reduce Motion, Low Power Mode), and no decoder exists until `play()`.
//

import UIKit

@MainActor
final class ShowcaseVideoCell: UICollectionViewCell {
    static let reuseID = "ShowcaseVideoCell"

    private static let scrimHeightRatio: CGFloat = 0.38
    private static let badgeSide: CGFloat = 24

    private let playerView = LoopingPreviewPlayerView()
    private let scrim = ShowcaseScrimView()
    private let nameLabel = UILabel()
    private let motionBadge = UIImageView()

    override init(frame: CGRect) {
        super.init(frame: frame)

        contentView.backgroundColor = Theme.Color.cellWell
        contentView.layer.cornerRadius = Theme.Radius.lg
        contentView.layer.cornerCurve = .continuous
        contentView.clipsToBounds = true

        nameLabel.font = Theme.Typography.subheadline
        // See `ShowcaseTemplateCell`: ink that floats over photography takes the
        // toast token, because it has no app surface to borrow from.
        nameLabel.textColor = Theme.Color.textOnToast
        nameLabel.adjustsFontForContentSizeCategory = true
        nameLabel.numberOfLines = 1
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.applyShowcaseCaptionShadow()

        // Says "this one moves" even when it is not moving — which is exactly the
        // case under Reduce Motion and Low Power Mode, where the card is a still.
        motionBadge.contentMode = .center
        motionBadge.tintColor = Theme.Color.textOnToast
        motionBadge.backgroundColor = Theme.Color.toast.withAlphaComponent(0.55)
        motionBadge.layer.cornerRadius = Self.badgeSide / 2
        motionBadge.layer.cornerCurve = .continuous
        motionBadge.clipsToBounds = true
        motionBadge.image = UIImage(
            systemName: "play.fill",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold))

        for subview in [playerView, scrim, nameLabel, motionBadge] as [UIView] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            contentView.addSubview(subview)
        }

        NSLayoutConstraint.activate([
            playerView.topAnchor.constraint(equalTo: contentView.topAnchor),
            playerView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            playerView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            playerView.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),

            scrim.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrim.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrim.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            scrim.heightAnchor.constraint(
                equalTo: contentView.heightAnchor, multiplier: Self.scrimHeightRatio),

            nameLabel.leadingAnchor.constraint(
                equalTo: contentView.leadingAnchor, constant: Theme.Spacing.sm),
            nameLabel.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.sm),
            nameLabel.bottomAnchor.constraint(
                equalTo: contentView.bottomAnchor, constant: -Theme.Spacing.sm),

            motionBadge.topAnchor.constraint(
                equalTo: contentView.topAnchor, constant: Theme.Spacing.xs),
            motionBadge.trailingAnchor.constraint(
                equalTo: contentView.trailingAnchor, constant: -Theme.Spacing.xs),
            motionBadge.widthAnchor.constraint(equalToConstant: Self.badgeSide),
            motionBadge.heightAnchor.constraint(equalToConstant: Self.badgeSide),
        ])

        isAccessibilityElement = true
        accessibilityTraits = .button
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The same press spring the gallery's cards and `ShowcaseTemplateCell` use —
    /// one press feel across the app.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick),
                delay: 0,
                usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
                initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                self.transform = self.isHighlighted
                    ? CGAffineTransform(scaleX: 0.96, y: 0.96) : .identity
            }
        }
    }

    func configure(name: String, identifier: String, poster: UIImage?, loopURL: URL?) {
        nameLabel.text = name
        accessibilityIdentifier = identifier
        accessibilityLabel = name
        // The play glyph is a fact stated only in pixels.
        accessibilityValue = String(localized: "Video")
        playerView.configure(loopURL: loopURL, poster: poster)
    }

    func play() { playerView.play() }
    func stop() { playerView.stop() }

    override func prepareForReuse() {
        super.prepareForReuse()
        // Releases the decoder AND the poster: whatever is in flight belongs to
        // the showcase this cell used to be.
        playerView.stop()
        playerView.configure(loopURL: nil, poster: nil)
        nameLabel.text = nil
        accessibilityValue = nil
    }
}
