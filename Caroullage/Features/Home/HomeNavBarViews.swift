//
//  HomeNavBarViews.swift
//  Caroullage
//
//  Step 07 — Home's header.
//
//  Losing the large title bought 62pt back for the content below it — see the
//  comment on `navigationItem.largeTitleDisplayMode` in HomeViewController's
//  `viewDidLoad` for where that space goes — but it left the top of the app
//  reading as a system screen label: a small centred word over a transparent
//  bar. This is the front door of a creative app, and it should say whose app
//  it is and what the app sells.
//
//  Two pieces, both leaning on what the design system already has: the brand
//  lockup (the icon's own mark and glyph, so the icon, the onboarding splash
//  and the header agree), and the Pro button, which carries the brand gradient
//  `GradientLayerButton` already knows how to paint and opens the paywall.
//

import UIKit

// MARK: - Brand mark

/// The app's own icon, at header size.
///
/// This was a gradient squircle with `square.stack.3d.up.fill` on it — an
/// invented mark that merely resembled the icon. The icon is a real drawing
/// (the white collage card over its fanned pair), so a lockup carrying an
/// approximation of it was showing users a logo the app does not have.
///
/// `AppIcon` cannot be loaded with `UIImage(named:)`, so the artwork is also
/// published as the `BrandMark` image set. The light rendition is used in both
/// appearances deliberately: it carries its own orange ground, so it holds the
/// same contrast on a dark screen as on a light one, and stays the mark people
/// already recognise from their home screen.
@MainActor
final class BrandMarkView: UIImageView {

    init(side: CGFloat = 30) {
        super.init(frame: .zero)

        image = UIImage(named: "BrandMark")
        contentMode = .scaleAspectFill
        clipsToBounds = true
        // The icon art is square and full-bleed, so it takes the icon's own
        // corner treatment rather than a circle.
        layer.cornerRadius = side * 0.28
        layer.cornerCurve = .continuous

        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: side),
            heightAnchor.constraint(equalToConstant: side),
        ])

        isAccessibilityElement = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Brand lockup

/// Mark plus wordmark, for the navigation bar's leading side.
///
/// Read as one element by assistive technology: two labels ("Caroullage", and
/// an unnamed image) would make the app's own name arrive twice.
@MainActor
final class BrandLockupView: UIView {

    init(title: String) {
        super.init(frame: .zero)

        let wordmark = UILabel()
        wordmark.text = title
        wordmark.font = Theme.Typography.title2
        wordmark.textColor = Theme.Color.textPrimary
        wordmark.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [BrandMarkView(), wordmark])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        isAccessibilityElement = true
        accessibilityLabel = title
        accessibilityTraits = .header
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }
}

// MARK: - Pro button

/// The paywall's entry point from the app's front door.
///
/// Gradient-filled rather than tinted: this is the one control in the bar that
/// is asking for something, and it has to win against a screen of photography
/// without shouting over the content below it.
///
/// It is not shown at all once premium is unlocked — a "Pro" button that leads
/// to a paywall you have already paid is a dead end, and the tiny gain of a
/// status badge is not worth a permanent CTA in the header.
@MainActor
final class ProBadgeButton: GradientLayerButton {

    private let action: () -> Void

    init(title: String, action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)

        // The glyph takes the button's tintColor, NOT `baseForegroundColor` — and
        // a bar button's custom view inherits the navigation bar's tint, so
        // without this the sparkle came out in the bar's dark ink while the word
        // beside it was white. The floating "Start Editing" pill sets both for
        // the same reason.
        tintColor = Theme.Color.textOnAccent

        // `.plain()`, not `.filled()`: the gradient IS the backing layer, so a
        // filled configuration only adds a background that has to be cleared
        // again.
        var config = UIButton.Configuration.plain()
        config.title = title
        config.imagePadding = 5
        config.attributedTitle = AttributedString(
            title, attributes: AttributeContainer([
                .font: Theme.Typography.rounded(13, .bold, .caption1),
            ]))
        config.contentInsets = NSDirectionalEdgeInsets(
            top: 7, leading: 12, bottom: 7, trailing: 13)
        config.baseForegroundColor = Theme.Color.textOnAccent
        // `.capsule` states the intent once and survives re-layout; a manual
        // cornerRadius on a configured button is overwritten by its own updates.
        config.cornerStyle = .capsule
        configuration = config

        useBrandGradient()
        refreshGlyph()
        // The glyph's colour is baked, so it has to be re-baked when the
        // appearance flips — exactly why `useBrandGradient` registers too.
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: Self, _) in
            button.refreshGlyph()
        }
        layer.cornerCurve = .circular

        addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.action()
        }, for: .touchUpInside)
        addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        addTarget(self, action: #selector(pressUp),
                  for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        accessibilityIdentifier = "homeProButton"
        accessibilityLabel = title
        accessibilityHint = String(localized: "Unlocks every template, export and tool.")
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// The sparkle, with its colour baked in rather than tinted.
    ///
    /// A template symbol inside a bar button item comes out pure black: the
    /// navigation bar renders bar-item content its own way and neither the
    /// button's `tintColor` nor its `baseForegroundColor` reaches the image —
    /// which is why the title was white beside a black sparkle, and why the
    /// same configuration works on the floating "Start Editing" pill, which is
    /// not in a bar. `.alwaysOriginal` carries the colour past all of that.
    ///
    /// Bigger and heavier than the label beside it: at 12pt the sparkle read as
    /// punctuation. It is the part that says "premium".
    private func refreshGlyph() {
        configuration?.image = UIImage(
            systemName: "sparkles",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .heavy)
        )?.withTintColor(
            Theme.Color.textOnAccent.resolvedColor(with: traitCollection),
            renderingMode: .alwaysOriginal)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // A capsule's radius is half its height, and the backing layer is ours
        // to round — `.capsule` shapes the configuration's background, which is
        // clear here so the gradient can show.
        layer.cornerRadius = bounds.height / 2
    }

    /// The same press spring every card in the app uses, so the header answers
    /// the touch the way the content does.
    @objc private func pressDown() {
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = CGAffineTransform(scaleX: 0.94, y: 0.94)
        }
    }

    @objc private func pressUp() {
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.quick), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.transform = .identity
        }
    }
}
