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
    private var activeToolID: EditorTool.ID?

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
            separator.heightAnchor.constraint(equalToConstant: 1 / UIScreen.main.scale),

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
}

// MARK: - Tool button

@MainActor
private final class ToolButton: UIControl {

    let toolID: EditorTool.ID
    private let icon = UIImageView()
    private let label = UILabel()

    init(tool: EditorTool) {
        self.toolID = tool.id
        super.init(frame: .zero)

        icon.image = UIImage(systemName: tool.systemImage)
        icon.contentMode = .scaleAspectFit
        icon.preferredSymbolConfiguration = UIImage.SymbolConfiguration(pointSize: 18, weight: .medium)

        label.text = tool.title
        label.font = Theme.Typography.tabLabel
        label.textAlignment = .center

        let stack = UIStackView(arrangedSubviews: [icon, label])
        stack.axis = .vertical
        stack.alignment = .center
        stack.spacing = 3
        stack.isUserInteractionEnabled = false
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            icon.heightAnchor.constraint(equalToConstant: 22),
            widthAnchor.constraint(greaterThanOrEqualToConstant: 58),
        ])
        setActive(false)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Indigo marks *which thing is chosen*; ink is ordinary chrome.
    func setActive(_ isActive: Bool) {
        let colour = isActive ? Theme.Color.accent : Theme.Color.textSecondary
        icon.tintColor = colour
        label.textColor = colour
    }

    override var isHighlighted: Bool {
        didSet { alpha = isHighlighted ? 0.55 : 1 }
    }
}

// MARK: - Context chip

@MainActor
private final class ContextChip: UIControl {

    init(title: String, systemImage: String) {
        super.init(frame: .zero)

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
