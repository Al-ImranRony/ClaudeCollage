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
//  The active tool's icon ANIMATES — a repeating SF Symbol effect chosen per tool
//  (see `EditorTool.Emphasis`) — and no other icon in the rail does. That is the
//  rail's answer to "which tool am I in": colour alone has to be read, where the
//  one moving thing on the strip is found without looking for it. Both editors
//  get it from here; there is no second copy of this rail to keep in step.
//

import UIKit

@MainActor
public final class EditorToolRail: UIView {

    public var onSelect: ((EditorTool.ID) -> Void)?
    public var onDismissContext: (() -> Void)?

    /// Content height above the safe-area inset.
    public static let contentHeight: CGFloat = 52

    private let scrollView = UIScrollView()
    private let stack = UIStackView()
    private var baseTools: [EditorTool] = []
    private var context: EditorRailContext?

    /// The setter is private: only `setActiveTool` and the stale-highlight guard
    /// in `rebuild()` may change this. The getter is left at the default
    /// (internal) access level so tests can assert the highlight was cleared.
    private(set) var activeToolID: EditorTool.ID?

    /// Flat hairline width, matching the codebase's other hand-drawn seams
    /// (`CarouselStripLayout.seamWidth`, `EmptyCellChrome.outlineWidth`) rather
    /// than a `UIScreen.main.scale`-derived value. `UIScreen.main` is deprecated
    /// as of iOS 26 and would misreport the scale on an external display anyway.
    private static let separatorHeight: CGFloat = 1

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

        scrollView.showsHorizontalScrollIndicator = false
        // The rail reaches the screen edge, so the automatic behaviour would hand
        // the home-indicator inset straight back as content inset.
        scrollView.contentInsetAdjustmentBehavior = .never
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(scrollView)

        stack.axis = .horizontal
        stack.alignment = .center
        stack.spacing = Theme.Spacing.xxs
        stack.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(stack)

        NSLayoutConstraint.activate([
            separator.topAnchor.constraint(equalTo: topAnchor),
            separator.leadingAnchor.constraint(equalTo: leadingAnchor),
            separator.trailingAnchor.constraint(equalTo: trailingAnchor),
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
                                           constant: Theme.Spacing.xs),
            stack.trailingAnchor.constraint(equalTo: scrollView.contentLayoutGuide.trailingAnchor,
                                            constant: -Theme.Spacing.xs),
            stack.heightAnchor.constraint(equalTo: scrollView.frameLayoutGuide.heightAnchor),
        ])
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
        self.context = context
        rebuild()
        if context != nil {
            scrollView.setContentOffset(.zero, animated: false)
        }
    }

    public func setActiveTool(_ id: EditorTool.ID?) {
        activeToolID = id
        for case let button as ToolButton in stack.arrangedSubviews {
            button.setActive(button.toolID == id)
        }
    }

    private func rebuild() {
        for view in stack.arrangedSubviews {
            stack.removeArrangedSubview(view)
            view.removeFromSuperview()
        }

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
        setActiveTool(activeToolID)
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
    func toolButton(for id: EditorTool.ID) -> UIControl? {
        stack.arrangedSubviews
            .compactMap { $0 as? ToolButton }
            .first(where: { $0.toolID == id })
    }
}

// MARK: - Tool button

@MainActor
private final class ToolButton: UIControl {

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

    let toolID: EditorTool.ID
    private let emphasis: EditorTool.Emphasis
    private let icon = UIImageView()
    private let label = UILabel()

    /// Optional so the first `setActive` always applies, however it is called.
    /// The rail calls `setActiveTool` on every rebuild, including rebuilds that
    /// change nothing, and restarting a running symbol effect on each of those
    /// makes the icon stutter.
    private var isActiveState: Bool?

    init(tool: EditorTool) {
        self.toolID = tool.id
        self.emphasis = tool.emphasis
        super.init(frame: .zero)

        isAccessibilityElement = true
        accessibilityTraits = .button

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
        ])
        setActive(false)

        // Reduce Motion is a setting, not a trait, so it does not arrive through
        // `registerForTraitChanges` like light/dark does. Target/selector rather
        // than a block observer: the block form would have to capture this
        // MainActor-isolated, non-Sendable view inside a `@Sendable` closure,
        // which Swift 6 rejects outright.
        NotificationCenter.default.addObserver(
            self, selector: #selector(reduceMotionChanged),
            name: UIAccessibility.reduceMotionStatusDidChangeNotification, object: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Indigo marks *which thing is chosen*; ink is ordinary chrome.
    func setActive(_ isActive: Bool) {
        let wasActive = isActiveState
        guard wasActive != isActive else { return }
        isActiveState = isActive

        let colour = isActive ? Theme.Color.accent : Theme.Color.textSecondary
        icon.tintColor = colour
        label.textColor = colour

        // The pop only plays on a real transition into "chosen" — never on the
        // `setActive(false)` in init, and never on a rebuild that re-asserts a
        // selection the button already had.
        if isActive, wasActive != nil { playSelectionPop() }
        updateSymbolEffect()
    }

    /// A spring-settled overshoot: the icon appears a fifth larger and rides back
    /// down. Skipped entirely under Reduce Motion — the colour change alone still
    /// says which tool is chosen, and the repeating effect is suppressed there
    /// too, so nothing in the rail moves.
    private func playSelectionPop() {
        guard !Theme.Motion.isReduced else { return }
        icon.transform = CGAffineTransform(
            scaleX: Self.selectionPopScale, y: Self.selectionPopScale)
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.standard),
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction, .beginFromCurrentState]
        ) {
            self.icon.transform = .identity
        }
    }

    /// Starts the active tool's repeating symbol effect, or takes it away.
    ///
    /// Exactly one button in the rail runs an effect at a time, because exactly
    /// one tool is active. A strip where every icon moved would be a strip that
    /// pointed at nothing.
    private func updateSymbolEffect() {
        icon.removeAllSymbolEffects(options: .speed(2), animated: true)
        // A loop that never stops is the one animation a user who has asked for
        // less motion cannot look away from, so Reduce Motion removes it rather
        // than shortening it — the accent colour is already carrying the state.
        guard isActiveState == true, !Theme.Motion.isReduced else { return }

        switch emphasis {
        case .pulse:
            // Indefinite: runs until removed, no repeat option needed.
            icon.addSymbolEffect(.pulse, options: .repeating, animated: true)
        case .variableColor:
            icon.addSymbolEffect(
                .variableColor.iterative.hideInactiveLayers, options: .repeating, animated: true)
        case .bounce:
            icon.addSymbolEffect(.bounce, options: .repeating, animated: true)
        case .wiggle:
            if #available(iOS 18.0, *) {
                icon.addSymbolEffect(.wiggle, options: .repeating, animated: true)
            } else {
                icon.addSymbolEffect(.bounce, options: .repeating, animated: true)
            }
        case .rotate:
            if #available(iOS 18.0, *) {
                icon.addSymbolEffect(.rotate, options: .repeating, animated: true)
            } else {
                icon.addSymbolEffect(.bounce, options: .repeating, animated: true)
            }
        }
    }

    @objc private func reduceMotionChanged() {
        updateSymbolEffect()
    }

    /// The same press spring the cards use, rather than the flat alpha dip this
    /// had before. A rail button is the most-tapped control in the editor, so it
    /// is the one that most wants to feel like it is being pushed.
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
                    ? CGAffineTransform(scaleX: Self.pressScale, y: Self.pressScale)
                    : .identity
                self.alpha = self.isHighlighted ? 0.75 : 1
            }
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
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}
