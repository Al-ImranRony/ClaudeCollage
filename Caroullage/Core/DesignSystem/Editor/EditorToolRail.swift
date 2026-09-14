//
//  EditorToolRail.swift
//  Caroullage
//
//  The editors' bottom tool rail. It holds a base tool set and can INSERT a
//  contextual group ahead of it when something on the canvas is selected — the
//  base tools are never removed, they scroll. A rail that swapped its contents
//  wholesale would make users hunt for a control that moved.
//
//  The rail's background reaches the bottom screen edge while its content stays
//  inside the safe area, which is what keeps the old "no dead band" behaviour
//  without the full-height scroll view that behaviour was originally built around.
//
//  With no context inserted the base tools divide the rail's width equally — the
//  rule a tab bar uses — so five tools are five columns, not a cluster at the
//  leading edge with dead space after it. Once a context is inserted the tools
//  keep their natural widths and a 4pt gap: on a phone the strip overflows and
//  scrolls, and on a rail wide enough to hold everything the group stays packed
//  at the leading edge rather than being spread thin across an iPad.
//
//  The active tool is marked three ways at once, and only one of them moves. The
//  accent colour and a soft capsule behind the icon carry the state for as long as
//  the tool is chosen. On the transition INTO chosen, the icon pops and plays one
//  pass of its per-tool SF Symbol effect (see `EditorTool.Emphasis`), the way a
//  hover state acknowledges a pointer — and then it rests. Both editors get it
//  from here; there is no second copy of this rail to keep in step.
//

import UIKit

@MainActor
public final class EditorToolRail: UIView {

    public var onSelect: ((EditorTool.ID) -> Void)?
    public var onDismissContext: (() -> Void)?

    /// Content height above the safe-area inset.
    public static let contentHeight: CGFloat = 52

    private let scrollView = EditorControlScrollView()
    private let stack = UIStackView()
    private var baseTools: [EditorTool] = []
    private var context: EditorRailContext?

    /// Stretches the strip to the rail's width so the base tools can share it
    /// as equal columns. Active only while there is no context: with one, the
    /// tools sit at their natural widths and this would spread them apart.
    private var fillWidthConstraint: NSLayoutConstraint?

    /// The setter is private: only `setActiveTool` and the stale-highlight guard
    /// in `rebuild()` may change this. The getter is left at the default
    /// (internal) access level so tests can assert the highlight was cleared.
    private(set) var activeToolID: EditorTool.ID?

    /// Flat hairline width, matching the codebase's other hand-drawn seams
    /// (`CarouselStripLayout.seamWidth`, `EmptyCellChrome.outlineWidth`) rather
    /// than a `UIScreen.main.scale`-derived value. `UIScreen.main` is deprecated
    /// as of iOS 26 and would misreport the scale on an external display anyway.
    private static let separatorHeight: CGFloat = 1

    /// The rail's horizontal content inset. Also the inset of its top hairline,
    /// which stops short of the edges so it reads as the divider between two
    /// tiers of one sheet rather than as the top edge of a second bar.
    private static let horizontalInset: CGFloat = Theme.Spacing.md

    /// The gap between tools while the strip is scrolling (a context inserted).
    private static let scrollingSpacing: CGFloat = Theme.Spacing.xxs

    /// The accessibility identifiers of every tool button currently in the rail,
    /// in leading-to-trailing order. The chip and the divider are not tools.
    public var visibleToolIdentifiers: [String] {
        stack.arrangedSubviews
            .compactMap { ($0 as? UIControl)?.accessibilityIdentifier }
            .filter { $0 != Self.chipIdentifier }
    }

    private static let chipIdentifier = "editorRailContextChip"

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupSubviews() {
        let separator = UIView()
        separator.backgroundColor = Theme.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        // The rail reaches the screen edge, so the automatic behaviour would hand
        // the home-indicator inset straight back as content inset.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Self.scrollingSpacing
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Self.horizontalInset),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Self.horizontalInset),
            separator.heightAnchor.constraint(equalToConstant: Self.separatorHeight),

            // Content sits inside the safe area; the view's background does not.
            scrollView.topAnchor.constraint(equalTo: topAnchor),
            scrollView.leadingAnchor.constraint(equalTo: leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor),
            scrollView.heightAnchor.constraint(equalToConstant: Self.contentHeight),

            stack.topAnchor.constraint(equalTo: scrollView.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scrollView.contentLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.leadingAnchor,
                                           constant: Self.horizontalInset),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                            constant: -Self.horizontalInset),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])

        // At least as wide as the rail, so a base tool set that fits is spread
        // across the whole strip; a wider set simply overflows and scrolls.
        let fill = stack.widthAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.widthAnchor,
            constant: -2 * Self.horizontalInset)
        fill.isActive = true
        fillWidthConstraint = fill
    }

    // MARK: - Content

    public func setBaseTools(_ tools: [EditorTool]) {
        baseTools = tools
        rebuild()
    }

    /// Sets or clears the contextual group. Passing a new context replaces the old
    /// one rather than adding to it.
    ///
    /// This does not itself choose what is highlighted: a previously active tool
    /// (set via `setActiveTool`) stays highlighted only if a tool with that same
    /// identifier is still present after the change — in the new context's tools
    /// or the base tools. Otherwise the active highlight is silently cleared, so
    /// a selection can never survive a context change and mislabel an unrelated
    /// tool as chosen.
    public func setContext(_ context: EditorRailContext?) {
        // The video editor re-selects a clip into the same Clip context on every
        // tap; rebuilding a dozen buttons for a strip that is not changing is
        // wasted work, and it would replay the scroll-to-start below.
        guard context != self.context else { return }
        self.context = context
        rebuild()
        if context != nil {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    public func setActiveTool(_ id: EditorTool.ID?) {
        activeToolID = id
        applyActiveTool(animated: true)
    }

    private func applyActiveTool(animated: Bool) {
        for case let button as ToolButton in stack.arrangedSubviews {
            button.setActive(button.toolID == activeToolID, animated: animated)
        }
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

        // Equal columns while the base tools have the strip to themselves. With
        // a context inserted the chip and the divider share the stack, so equal
        // columns would hand each of them a tool's width; the strip hugs its
        // content instead, scrolling on a phone and leading-aligned on an iPad.
        stack.distribution = context == nil ? .fillEqually : .fill
        fillWidthConstraint?.isActive = context == nil

        if let context {
            stack.addArrangedSubview(makeChip(context))
            for tool in context.tools {
                stack.addArrangedSubview(makeButton(tool))
            }
            stack.addArrangedSubview(makeDivider())
        }
        for tool in baseTools {
            stack.addArrangedSubview(makeButton(tool))
        }

        // A tool that no longer exists after this rebuild must not stay "active"
        // in name only — otherwise an unrelated tool that happens to reuse the
        // same identifier in a later context would light up unchosen.
        let presentToolIDs = stack.arrangedSubviews.compactMap { ($0 as? ToolButton)?.toolID }
        if let activeToolID, !presentToolIDs.contains(activeToolID) {
            self.activeToolID = nil
        }
        // Un-animated: these are fresh buttons showing a selection that already
        // existed, not a tool being chosen. A context change that leaves a base
        // panel open must not replay that panel's tool pop.
        applyActiveTool(animated: false)
    }

    // MARK: - Subview factories

    private func makeButton(_ tool: EditorTool) -> ToolButton {
        let button = ToolButton(tool: tool)
        button.accessibilityIdentifier = tool.accessibilityIdentifier
        button.accessibilityLabel = tool.title
        button.addAction(UIAction { [weak self] _ in
            Haptics.selectionChanged()
            self?.onSelect?(tool.id)
        }, for: .touchUpInside)
        return button
    }

    private func makeChip(_ context: EditorRailContext) -> UIControl {
        let chip = ContextChip(title: context.chipTitle, systemImage: context.chipSystemImage)
        chip.accessibilityIdentifier = Self.chipIdentifier
        chip.accessibilityLabel = "\(context.chipTitle) selected. Double tap to deselect."
        chip.addAction(UIAction { [weak self] _ in
            Haptics.tap()
            self?.setContext(nil)
            self?.onDismissContext?()
        }, for: .touchUpInside)
        return chip
    }

    private func makeDivider() -> UIView {
        let container = UIView()
        let line = UIView()
        line.backgroundColor = Theme.Color.separator
        line.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(line)
        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: Theme.Spacing.sm),
            line.widthAnchor.constraint(equalToConstant: 1),
            line.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            line.topAnchor.constraint(equalTo: container.topAnchor, constant: Theme.Spacing.sm),
            line.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -Theme.Spacing.sm),
        ])
        return container
    }

    // MARK: - Test seams

    /// Drives the same path a real tap does, without needing a window or a hit test.
    func simulateTap(toolID: EditorTool.ID) {
        guard let button = stack.arrangedSubviews
            .compactMap({ $0 as? ToolButton })
            .first(where: { $0.toolID == toolID }) else { return }
        button.sendActions(for: .touchUpInside)
    }

    func simulateChipDismiss() {
        guard let chip = stack.arrangedSubviews
            .compactMap({ $0 as? UIControl })
            .first(where: { $0.accessibilityIdentifier == Self.chipIdentifier }) else { return }
        chip.sendActions(for: .touchUpInside)
    }

    /// The tool button currently in the rail for a given tool identifier, if any.
    /// Exposed only so tests can inspect real geometry/hit-testing; production
    /// code has no need to reach into an individual button.
    func toolButton(for id: EditorTool.ID) -> ToolButton? {
        stack.arrangedSubviews
            .compactMap { $0 as? ToolButton }
            .first(where: { $0.toolID == id })
    }

    /// The context chip, if one is showing. A test seam, like `toolButton(for:)`.
    func contextChipForLayout() -> UIControl? {
        stack.arrangedSubviews
            .compactMap { $0 as? UIControl }
            .first(where: { $0.accessibilityIdentifier == Self.chipIdentifier })
    }
}

// MARK: - Tool button

@MainActor
final class ToolButton: UIControl {

    /// How far the icon overshoots when a tool becomes the active one.
    ///
    /// The pop is what makes the selection feel like it landed. It is deliberately
    /// bigger than the press scale below — the press is a response to the finger
    /// and should stay under it, the pop is the app answering and should read
    /// from across the strip.
    private static let selectionPopScale: CGFloat = 1.22

    /// The press scale. Slightly deeper than the 0.96 the cards use because a
    /// 58pt-wide control has less area for the same proportion to register in.
    private static let pressScale: CGFloat = 0.92

    /// The soft capsule behind the active icon. Wide enough to read as a well
    /// the icon sits in rather than a halo hugging it.
    private static let wellSize = CGSize(width: 44, height: 28)

    let toolID: EditorTool.ID
    private let emphasis: EditorTool.Emphasis
    private let well = UIView()
    private let icon = UIImageView()
    private let label = UILabel()

    /// Optional so the first `setActive` always applies, however it is called.
    private var isActiveState: Bool?

    /// How many times this button has played its selection moment. A test
    /// seam: `UIImageView` has no getter for the effects it is running, and the
    /// owner's complaint was an effect that never stopped, so the count is what
    /// pins "once per selection, and not again on a rebuild".
    private(set) var emphasisPlayCount = 0

    init(tool: EditorTool) {
        self.toolID = tool.id
        self.emphasis = tool.emphasis
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityTraits = .button

        well.backgroundColor = Theme.Color.accentSoft
        well.layer.cornerRadius = Self.wellSize.height / 2
        well.layer.cornerCurve = .continuous
        well.isUserInteractionEnabled = false
        well.translatesAutoresizingMaskIntoConstraints = false
        addSubview(well)

        icon.image = UIImage(systemName: tool.systemImage)
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        label.text = tool.title
        label.font = Theme.Typography.tabLabel
        label.textAlignment = .center
        // The row is a flat 52pt that does not scale with Dynamic Type, so give
        // the label somewhere to go at the largest accessibility sizes instead
        // of clipping or overflowing into the neighbouring button.
        label.numberOfLines = 1
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.7

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            // Pinned top/bottom (mirroring ContextChip's leading/trailing/top/bottom
            // pins) rather than centerYAnchor-only: a UIStackView with
            // alignment = .center does not stretch a cross-axis arranged subview,
            // so without a top/bottom pin the button has no source for its own
            // height and resolves to zero — invisible to hit-testing even though
            // the icon still draws (clipsToBounds is off).
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
            icon.heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 58),

            well.centerXAnchor.constraint(equalTo: icon.centerXAnchor),
            well.centerYAnchor.constraint(equalTo: icon.centerYAnchor),
            well.widthAnchor.constraint(equalToConstant: Self.wellSize.width),
            well.heightAnchor.constraint(equalToConstant: Self.wellSize.height),
        ])
        setActive(false, animated: false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Indigo marks *which thing is chosen*; ink is ordinary chrome.
    ///
    /// `animated` is the difference between a tool being chosen and a fresh
    /// button showing a choice that already existed: only the former earns the
    /// pop and the one-shot symbol effect.
    func setActive(_ isActive: Bool, animated: Bool) {
        guard isActiveState != isActive else { return }
        isActiveState = isActive

        let colour = isActive ? Theme.Color.accent : Theme.Color.textSecondary
        icon.tintColor = colour
        label.textColor = colour
        label.font = isActive
            ? Theme.Typography.rounded(10, .bold, .caption2)
            : Theme.Typography.tabLabel
        if isActive {
            accessibilityTraits.insert(.selected)
        } else {
            accessibilityTraits.remove(.selected)
        }

        // A one-shot effect stays on the image view after its single pass, so
        // deselection is where it is taken off — eased out, in case the user
        // moved on before it finished. Selection removes it un-animated instead:
        // the new effect is added in the same turn and must not stack on a
        // removal that is still fading.
        icon.removeAllSymbolEffects(animated: !isActive)

        guard animated, !Theme.Motion.isReduced else {
            well.alpha = isActive ? 1 : 0
            well.transform = .identity
            return
        }
        if isActive {
            playSelection()
        } else {
            // From the presentation value, not the model's: a tool deselected
            // mid-bloom fades from wherever its well had got to, rather than
            // snapping to full opacity first.
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick),
                delay: 0,
                options: [.beginFromCurrentState]
            ) {
                self.well.alpha = 0
                self.well.transform = .identity
            }
        }
    }

    /// The moment of selection: the well blooms, the icon springs in from a
    /// fifth larger, and the tool's own symbol effect plays through once. None
    /// of it repeats — the colour and the well are what say "chosen" afterwards.
    private func playSelection() {
        well.alpha = 0
        well.transform = CGAffineTransform(scaleX: 0.6, y: 0.6)
        icon.transform = CGAffineTransform(
            scaleX: Self.selectionPopScale, y: Self.selectionPopScale)
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.standard),
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.well.alpha = 1
            self.well.transform = .identity
            self.icon.transform = .identity
        }
        emphasisPlayCount += 1
        playEmphasis()
    }

    /// One pass of the per-tool effect. Every effect is added `.nonRepeating`:
    /// `pulse` and `variableColor` are indefinite by default and would otherwise
    /// loop, and `bounce` used to be added `.repeating` on purpose.
    private func playEmphasis() {
        switch emphasis {
        case .pulse:
            icon.addSymbolEffect(.pulse, options: .nonRepeating)
        case .variableColor:
            icon.addSymbolEffect(.variableColor.iterative.hideInactiveLayers, options: .nonRepeating)
        case .bounce:
            icon.addSymbolEffect(.bounce, options: .nonRepeating)
        case .wiggle:
            if #available(iOS 18.0, *) {
                icon.addSymbolEffect(.wiggle, options: .nonRepeating)
            } else {
                icon.addSymbolEffect(.bounce, options: .nonRepeating)
            }
        case .rotate:
            if #available(iOS 18.0, *) {
                icon.addSymbolEffect(.rotate, options: .nonRepeating)
            } else {
                icon.addSymbolEffect(.bounce, options: .nonRepeating)
            }
        }
    }

    /// The same press spring every editor control uses. A rail button is the
    /// most-tapped control in the editor, so it is the one that most wants to
    /// feel like it is being pushed; it goes a touch deeper than the cards.
    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted, scale: Self.pressScale)
        }
    }
}

// MARK: - Context chip

@MainActor
private final class ContextChip: UIControl {

    init(title: String, systemImage: String) {
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityTraits = .button

        let icon = UIImageView(image: UIImage(systemName: systemImage))
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 11, weight: .semibold)
        icon.tintColor = Theme.Color.accent

        let label = UILabel()
        label.text = title
        label.font = Theme.Typography.tabLabel
        label.textColor = Theme.Color.accent

        let close = UIImageView(image: UIImage(systemName: "xmark"))
        close.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 9, weight: .bold)
        close.tintColor = Theme.Color.accent

        let stack = UIStackView(arrangedSubviews: [icon, label, close])
        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = 4
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        backgroundColor = Theme.Color.accentSoft
        layer.cornerRadius = Theme.Radius.sm
        layer.cornerCurve = .continuous

        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.xs),
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override var isHighlighted: Bool {
        didSet {
            guard isHighlighted != oldValue else { return }
            setPressed(isHighlighted)
        }
    }
}
