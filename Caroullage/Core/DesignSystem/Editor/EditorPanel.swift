//
//  EditorPanel.swift
//  Caroullage
//
//  The swap-in controls container that sits between the stage and the rail. One
//  tool's controls at a time — the collage editor previously stacked every control
//  it had into one long scroll, which reads as a settings form rather than an editor.
//
//  It paints the same surface as the rail beneath it, so panel and rail read as one
//  sheet with a single hairline along its top edge; the rail's own hairline is
//  inset and reads as a divider between the sheet's two tiers. The header is a
//  centred title with a round close chip at the trailing margin — the grammar the
//  reference editors share — rather than an uppercased caption with a bare ✕.
//
//  Hiding sets `isHidden` rather than removing the view, so the stage's height
//  animation has something stable to animate against.
//
//  `isHidden` must not be set directly by callers. It is written internally by
//  `show`/`hide` (via `setVisible`) and guarded by a generation counter so that
//  an interrupted animation's completion can't clobber a newer presentation.
//  Setting it from outside desyncs real visibility from `isPresenting`, after
//  which `hide` becomes a permanent no-op while the panel stays on screen.
//

import UIKit

@MainActor
public final class EditorPanel: UIView {

    /// A defensive floor so a caller that lays this out expecting it to
    /// self-size (rather than being given an explicit height) gets a visibly
    /// collapsed-looking panel instead of a silent zero-height view. Not a
    /// real size contract — a caller's explicit height constraint still wins,
    /// see the `.defaultLow` priority below.
    private static let minimumHeight: CGFloat = Theme.Spacing.xxl * 2

    public var onClose: (() -> Void)?
    public private(set) var isPresenting = false

    /// Exposed for tests and for the VC's own bookkeeping.
    public private(set) var currentTitle: String?

    /// Flat hairline width, matching the codebase's other hand-drawn seams
    /// (`CarouselStripLayout.seamWidth`, `EditorToolRail.separatorHeight`) rather
    /// than a `UIScreen.main.scale`-derived value. `UIScreen.main` is deprecated
    /// as of iOS 26 and would misreport the scale on an external display anyway.
    private static let separatorHeight: CGFloat = 1

    /// The close chip's diameter. A 28pt circle is the smallest that still reads
    /// as a button rather than a glyph, and it is what the header's height is
    /// built from.
    private static let closeDiameter: CGFloat = 28

    private let titleLabel = UILabel()
    private let closeButton = CloseChip()
    private let contentContainer = UIView()
    private var content: UIView?

    /// Incremented at the start of every `show`/`hide`. An animation
    /// completion captures the value in effect when it was scheduled and
    /// bails out if it no longer matches — that's what keeps an interrupted
    /// hide's completion from writing visibility/content state for a
    /// presentation that has since moved on.
    private var visibilityGeneration = 0

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        isHidden = true
        // Task 8's content isn't ours to trust the height of; without this,
        // anything taller than the panel bleeds past its edge over the rail
        // or the canvas instead of failing visibly.
        clipsToBounds = true
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupSubviews() {
        let separator = UIView()
        separator.backgroundColor = Theme.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        titleLabel.font = Theme.Typography.subheadline
        titleLabel.textColor = Theme.Color.textPrimary
        titleLabel.textAlignment = .center
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.accessibilityIdentifier = "editorPanelCloseButton"
        closeButton.accessibilityLabel = "Close"
        closeButton.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.onClose?()
        }, for: .touchUpInside)
        closeButton.translatesAutoresizingMaskIntoConstraints = false
        addSubview(closeButton)

        contentContainer.translatesAutoresizingMaskIntoConstraints = false
        addSubview(contentContainer)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
            separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight),

            // Explicit width/height, not just a center pin: a control sized only
            // by centerX/centerY constraints (with no intrinsic content driving
            // its bounds) resolves to a zero frame — it still draws via its
            // image view, but hit-testing at that point falls through to the
            // panel underneath. See EditorToolRail.ToolButton's regression test
            // for the same trap on a bare UIControl.
            closeButton.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.sm),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.md),
            closeButton.widthAnchor.constraint(equalToConstant: Self.closeDiameter),
            closeButton.heightAnchor.constraint(equalToConstant: Self.closeDiameter),

            // Centred on the PANEL, not on the space left beside the chip — a
            // title that sits a half-chip off centre is the kind of thing that
            // is felt before it is seen. The chip keeps its own clear zone on
            // both sides so a long title stops short of it symmetrically.
            titleLabel.centerXAnchor.constraint(equalTo: centerXAnchor),
            titleLabel.centerYAnchor.constraint(equalTo: closeButton.centerYAnchor),
            titleLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: leadingAnchor,
                constant: Theme.Spacing.md + Self.closeDiameter + Theme.Spacing.xs),
            titleLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: closeButton.leadingAnchor, constant: -Theme.Spacing.xs),

            contentContainer.topAnchor.constraint(equalTo: closeButton.bottomAnchor,
                                                  constant: Theme.Spacing.sm),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor,
                                                     constant: -Theme.Spacing.sm),
        ])

        // Defensive only: every internal constraint above consumes height,
        // none of them produce it, so a caller that lays this view out
        // expecting it to self-size (no explicit height of its own) would
        // otherwise silently collapse to zero — the same class of bug that
        // already bit Task 4. `.defaultLow` so a caller's explicit height
        // constraint still wins; this only stops the silent zero case.
        let minimumHeight = heightAnchor.constraint(greaterThanOrEqualToConstant: Self.minimumHeight)
        minimumHeight.priority = .defaultLow
        minimumHeight.isActive = true
    }

    // MARK: - Presentation

    public func show(_ view: UIView, title: String, animated: Bool) {
        visibilityGeneration += 1
        content?.removeFromSuperview()
        content = view

        titleLabel.text = title
        currentTitle = title

        view.translatesAutoresizingMaskIntoConstraints = false
        contentContainer.addSubview(view)
        NSLayoutConstraint.activate([
            view.topAnchor.constraint(equalTo: contentContainer.topAnchor),
            view.leadingAnchor.constraint(equalTo: contentContainer.leadingAnchor),
            view.trailingAnchor.constraint(equalTo: contentContainer.trailingAnchor),
            view.bottomAnchor.constraint(equalTo: contentContainer.bottomAnchor),
        ])

        isPresenting = true
        setVisible(true, animated: animated)
    }

    public func hide(animated: Bool) {
        guard isPresenting else { return }
        visibilityGeneration += 1
        isPresenting = false
        currentTitle = nil
        // Capture the view that's actually being hidden now, not whatever
        // `content` happens to point to when this completion eventually
        // fires — a `show` for a new panel can (and routinely does, in this
        // component's primary rapid-switching interaction) land before that
        // happens and replace `content` out from under us.
        let outgoing = content
        setVisible(false, animated: animated) { [weak self] in
            outgoing?.removeFromSuperview()
            if self?.content === outgoing {
                self?.content = nil
            }
        }
    }

    private func setVisible(_ visible: Bool, animated: Bool, completion: (() -> Void)? = nil) {
        // Captured now, checked when the animation completion fires: if a
        // later show/hide has since bumped the generation, this completion
        // is for a presentation that's no longer current and must not touch
        // `isHidden` or run its teardown — the newer show/hide already left
        // the view in the state it wants.
        let generation = visibilityGeneration
        guard animated, !Theme.Motion.isReduced else {
            isHidden = !visible
            alpha = visible ? 1 : 0
            completion?()
            return
        }
        if visible { isHidden = false; alpha = 0 }
        UIView.animate(withDuration: Theme.Motion.quick) {
            self.alpha = visible ? 1 : 0
        } completion: { _ in
            guard self.visibilityGeneration == generation else { return }
            self.isHidden = !visible
            completion?()
        }
    }

    // MARK: - Test seams

    func simulateClose() {
        closeButton.sendActions(for: .touchUpInside)
    }

    /// The close button itself. Exposed only so tests can inspect real
    /// geometry/hit-testing; production code has no need to reach past `onClose`.
    /// Mirrors `EditorToolRail.toolButton(for:)`.
    var closeButtonForHitTesting: UIButton { closeButton }

    /// The title label, for tests that assert the header's geometry.
    var titleLabelForLayout: UILabel { titleLabel }
}

// MARK: - Close chip

/// A round `controlFill` chip with a bold ✕ — the same close every reference
/// editor draws in its sheet header. A configured button so the circle is the
/// button's own background (never `layer.cornerRadius` on a configured button).
@MainActor
/// Draws 28pt; hits 44 — see `HitTargetButton`. The chip sits `Spacing.sm`
/// below the panel's top and `Spacing.md` from its trailing edge, which is
/// exactly the room the grown region needs.
private final class CloseChip: HitTargetButton {

    init() {
        super.init(frame: .zero)
        var config = UIButton.Configuration.filled()
        config.cornerStyle = .capsule
        config.baseBackgroundColor = Theme.Color.controlFill
        config.baseForegroundColor = Theme.Color.textPrimary
        config.image = UIImage(
            systemName: "xmark",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 11, weight: .bold))
        config.contentInsets = .zero
        configuration = config
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: 0.9)
        }
    }
}
