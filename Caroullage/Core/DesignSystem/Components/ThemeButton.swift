//
//  ThemeButton.swift
//  Caroullage
//
//  Step 05b Part B.
//
//  `Theme` hands out tokens; it never handed out controls, so every screen has
//  been assembling its own buttons from tokens and drifting a little each time —
//  different corner radii, different insets, haptics on some taps and not
//  others. This is the one button the app uses.
//
//  The styles are a hierarchy, not a palette: exactly one primary per screen,
//  secondary for the neutral alternative, tertiary for the low-stakes one, hero
//  for the single "make something" call to action. Two filled buttons on a
//  screen compete and neither wins, which is why `secondary` is deliberately
//  quiet rather than a lighter version of `primary`.
//

import UIKit

@MainActor
public final class ThemeButton: GradientLayerButton {

    public enum Style {
        /// Filled brand. The one action the screen is for.
        case primary
        /// Filled neutral. The alternative that is not the point.
        case secondary
        /// Unfilled, accent label. Low-stakes ("See all", "Cancel").
        case tertiary
        /// A soft-accent pill. The editors' "add something" affordances (Text,
        /// Sticker), which are peers rather than a primary and an alternative.
        case tinted
        /// The brand gradient under a large label. At most one per screen.
        case hero
    }

    private let style: Style

    public init(style: Style, title: String, image: UIImage? = nil, action: UIAction) {
        self.style = style
        super.init(frame: .zero)
        addAction(action, for: .touchUpInside)
        addAction(UIAction { _ in Haptics.tap() }, for: .touchUpInside)
        configure(title: title, image: image)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Appearance

    private func configure(title: String, image: UIImage?) {
        var config = UIButton.Configuration.plain()
        config.title = title
        config.image = image
        config.imagePadding = Theme.Spacing.xs
        config.contentInsets = NSDirectionalEdgeInsets(
            top: Theme.Spacing.sm, leading: Theme.Spacing.lg,
            bottom: Theme.Spacing.sm, trailing: Theme.Spacing.lg
        )

        let font = style == .hero ? Theme.Typography.title2 : Theme.Typography.button
        config.titleTextAttributesTransformer = UIConfigurationTextAttributesTransformer { incoming in
            var outgoing = incoming
            outgoing.font = font
            return outgoing
        }

        switch style {
        case .primary:
            config.baseForegroundColor = Theme.Color.textOnAccent
            config.background.backgroundColor = Theme.Color.accentStrong
        case .secondary:
            config.baseForegroundColor = Theme.Color.textPrimary
            config.background.backgroundColor = Theme.Color.controlFill
        case .tertiary:
            config.baseForegroundColor = Theme.Color.accentStrong
            config.background.backgroundColor = .clear
        case .tinted:
            // The ink is `accentStrong`, not `accent`: the wash is already
            // the indigo at 15%, and indigo ink on an indigo wash is a tint on
            // a tint. The ink reads, the wash carries the colour.
            config.baseForegroundColor = Theme.Color.accentStrong
            config.background.backgroundColor = Theme.Color.accentSoft
        case .hero:
            config.baseForegroundColor = Theme.Color.textOnAccent
            // The gradient is the button's own backing layer, so the
            // configuration must not paint a background over it.
            config.background.backgroundColor = .clear
            config.contentInsets = NSDirectionalEdgeInsets(
                top: Theme.Spacing.md, leading: Theme.Spacing.xl,
                bottom: Theme.Spacing.md, trailing: Theme.Spacing.xl
            )
        }

        config.background.cornerRadius = style == .hero ? Theme.Radius.lg : Theme.Radius.md
        configuration = config

        if style == .hero {
            layer.cornerRadius = Theme.Radius.lg
            layer.cornerCurve = .continuous
            useBrandGradient()
        }
    }

    // MARK: - Press feedback

    public override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            let scale: CGFloat = isHighlighted ? 0.96 : 1
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick),
                delay: 0,
                usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
                initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
                options: [.allowUserInteraction, .beginFromCurrentState]
            ) {
                // Reduce Motion asks for less movement, so the press answers
                // with opacity instead of scale rather than with nothing.
                if Theme.Motion.isReduced {
                    self.alpha = self.isHighlighted ? 0.7 : 1
                } else {
                    self.transform = CGAffineTransform(scaleX: scale, y: scale)
                }
            }
        }
    }
}
