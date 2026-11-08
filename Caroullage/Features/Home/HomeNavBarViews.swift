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
//  Three pieces, all leaning on what the design system already has: the
//  Settings tile (clear glass flush against the leading edge, indigo
//  `line.3.horizontal`), the wordmark after it, and the Pro button, which
//  carries the brand gradient `GradientLayerButton` already knows how to paint
//  and opens the paywall. `BrandMarkView` — the icon's own mark — stays for
//  screens that show it on its own; the header dropped it beside the tile.
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
/// published as the `BrandMark` image set — rendered from the same generator as
/// the icon (`main.swift brandmark 1 <imageset>`) rather than copied by hand.
/// It was copied by hand once, and it is why the lockup was still orange for a
/// while after the app was not.
///
/// The light rendition is used in both appearances deliberately: it carries its
/// own near-black ground, so it holds the same contrast on a dark screen as on
/// a light one, and stays the mark people already recognise from their home
/// screen.
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

/// The wordmark, for the navigation bar's leading side, after Settings.
///
/// Wordmark only: beside the Settings square, the icon's mark made two tiles in
/// a row and read as clutter. `BrandMarkView` stays for anywhere the mark
/// belongs on its own.
@MainActor
final class BrandLockupView: UIView {

    /// Room kept clear ahead of the wordmark — Home's Settings tile floats on
    /// the bar there, outside the bar's item layout.
    let leadingInset: CGFloat

    init(title: String, leadingInset: CGFloat = 0) {
        self.leadingInset = leadingInset
        super.init(frame: .zero)

        let wordmark = UILabel()
        wordmark.text = title
        wordmark.font = Theme.Typography.title2
        wordmark.textColor = Theme.Color.textPrimary
        wordmark.adjustsFontForContentSizeCategory = true

        let stack = UIStackView(arrangedSubviews: [wordmark])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xs
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: leadingInset),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
        ])

        // The label, not the container, is the element: the container's frame
        // includes the inset the Settings tile sits in.
        wordmark.accessibilityTraits = .header
        wordmark.accessibilityIdentifier = "homeBrandWordmark"
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
        // Out of tint dimming. When a sheet comes up (Settings, from the tile
        // beside this button), UIKit dims the tint of everything behind it. The
        // sparkle and the gradient are baked colours and ignore that, but the
        // title followed it, so "Pro" alone faded to grey while the rest of the
        // pill stayed bright, which read as a flicker. The sheet's own dimming
        // overlay still darkens the whole pill, evenly.
        tintAdjustmentMode = .normal

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

    /// The same press every card in the app uses (`setPressed`), so the header
    /// answers the touch the way the content does — and answers Reduce Motion
    /// with opacity, as they do.
    @objc private func pressDown() { setPressed(true, scale: 0.94) }

    @objc private func pressUp() { setPressed(false, scale: 0.94) }
}

// MARK: - Settings button

/// Settings, as the bar's leading control: a 44pt square of clear Liquid Glass
/// set flush against the screen's leading edge — square where it meets the
/// edge, rounded on its outer side, like a rubber block fixed to a wall —
/// carrying `line.3.horizontal` in indigo.
///
/// The one chromatic thing in Home's chrome, on purpose: the way into Settings
/// should be findable at a glance. The colour is `accent`, the indigo the design
/// system already reserves for selection, rather than a new hue — it clears
/// contrast in both appearances and stays clear of the red, green and amber that
/// `critical`, `success` and `warning` own.
///
/// 44pt, not the bar's full 54: iOS 26 caps a bar item's height at 44, and the
/// tile matches the bar's other controls.
///
/// The body is a `UIVisualEffectView` with an interactive `UIGlassEffect`, not
/// the `.glass()` button configuration: the configuration's glass ignores
/// per-corner shaping and draws a circle, and the square-to-the-wall shape is
/// the point. `cornerConfiguration` is the API that shapes glass. Interactive
/// glass sees the touch through its gesture recogniser even though the button
/// inside it is what is hit, so the press still gets the system's own swell.
/// iOS 17–18 have no glass: they get the chrome material and the app's press
/// spring.
@MainActor
final class SettingsGlassTile: UIView {

    static let side: CGFloat = 44
    /// The outer corners' radius. The edge-side corners stay square.
    private static let outerRadius: CGFloat = 14

    let button: UIButton
    private let body: UIVisualEffectView

    init(action: @escaping () -> Void) {
        let effect: UIVisualEffect
        if #available(iOS 26.0, *) {
            let glass = UIGlassEffect(style: .regular)
            glass.isInteractive = true
            effect = glass
        } else {
            effect = UIBlurEffect(style: .systemChromeMaterial)
        }
        body = UIVisualEffectView(effect: effect)

        var config = UIButton.Configuration.plain()
        config.contentInsets = .zero
        button = UIButton(configuration: config)

        super.init(frame: .zero)

        body.translatesAutoresizingMaskIntoConstraints = false
        addSubview(body)
        button.translatesAutoresizingMaskIntoConstraints = false
        body.contentView.addSubview(button)
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: Self.side),
            heightAnchor.constraint(equalToConstant: Self.side),
            body.topAnchor.constraint(equalTo: topAnchor),
            body.bottomAnchor.constraint(equalTo: bottomAnchor),
            body.leadingAnchor.constraint(equalTo: leadingAnchor),
            body.trailingAnchor.constraint(equalTo: trailingAnchor),
            button.topAnchor.constraint(equalTo: body.contentView.topAnchor),
            button.bottomAnchor.constraint(equalTo: body.contentView.bottomAnchor),
            button.leadingAnchor.constraint(equalTo: body.contentView.leadingAnchor),
            button.trailingAnchor.constraint(equalTo: body.contentView.trailingAnchor),
        ])

        refreshGlyph()
        refreshCorners()
        registerForTraitChanges([UITraitUserInterfaceStyle.self,
                                 UITraitAccessibilityContrast.self,
                                 UITraitLayoutDirection.self]) { (tile: Self, _) in
            tile.refreshGlyph()
            tile.refreshCorners()
        }

        button.addAction(UIAction { _ in action() }, for: .touchUpInside)
        button.addTarget(self, action: #selector(pressDown), for: [.touchDown, .touchDragEnter])
        button.addTarget(self, action: #selector(pressUp),
                         for: [.touchUpInside, .touchUpOutside, .touchCancel, .touchDragExit])

        // iPad with a pointer: the tile lifts under the cursor — the hover half
        // of the motion, where a device actually has hover.
        button.isPointerInteractionEnabled = true
        button.pointerStyleProvider = { [weak self] _, _, _ in
            guard let self else { return nil }
            return UIPointerStyle(effect: .lift(UITargetedPreview(view: self)))
        }

        button.accessibilityIdentifier = "homeSettingsButton"
        button.accessibilityLabel = String(localized: "Settings")
        // Bar controls do not grow with Dynamic Type, so at the accessibility
        // sizes a long press shows the control enlarged instead.
        button.showsLargeContentViewer = true
        button.largeContentTitle = String(localized: "Settings")
        button.largeContentImage = UIImage(systemName: "line.3.horizontal")
        button.addInteraction(UILargeContentViewerInteraction())
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// `line.3.horizontal`, with its colour baked in rather than tinted, so it
    /// keeps the indigo wherever it is hosted (a template symbol in the bar
    /// comes out in the bar's ink — the Pro button's sparkle hit the same wall).
    private func refreshGlyph() {
        button.configuration?.image = UIImage(
            systemName: "line.3.horizontal",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 18, weight: .bold)
        )?.withTintColor(
            Theme.Color.accent.resolvedColor(with: traitCollection),
            renderingMode: .alwaysOriginal)
    }

    /// Square on the edge side, rounded on the outer side — mirrored for
    /// right-to-left layouts, where the bar's leading edge is the right.
    private func refreshCorners() {
        let radius = Self.outerRadius
        let leadingIsLeft = effectiveUserInterfaceLayoutDirection == .leftToRight
        if #available(iOS 26.0, *) {
            body.cornerConfiguration = leadingIsLeft
                ? .uniformEdges(leftRadius: .fixed(0), rightRadius: .fixed(radius))
                : .uniformEdges(leftRadius: .fixed(radius), rightRadius: .fixed(0))
        } else {
            body.clipsToBounds = true
            body.layer.cornerRadius = radius
            body.layer.cornerCurve = .continuous
            body.layer.maskedCorners = leadingIsLeft
                ? [.layerMaxXMinYCorner, .layerMaxXMaxYCorner]
                : [.layerMinXMinYCorner, .layerMinXMaxYCorner]
        }
    }

    @objc private func pressDown() {
        Haptics.softTap()
        if #unavailable(iOS 26.0) { setPressed(true, scale: 0.92) }
    }

    @objc private func pressUp() {
        if #unavailable(iOS 26.0) { setPressed(false, scale: 0.92) }
    }
}
