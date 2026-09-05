//
//  EditorPanel.swift
//  Caroullage
//
//  The swap-in controls container that sits between the stage and the rail. One
//  tool's controls at a time — the collage editor previously stacked every control
//  it had into one long scroll, which reads as a settings form rather than an editor.
//
//  Hiding sets `isHidden` rather than removing the view, so the stage's height
//  animation has something stable to animate against.
//

import UIKit

@MainActor
public final class EditorPanel: UIView {

    public var onClose: (() -> Void)?
    public private(set) var isPresenting = false

    /// Exposed for tests and for the VC's own bookkeeping.
    public private(set) var currentTitle: String?

    /// Flat hairline width, matching the codebase's other hand-drawn seams
    /// (`CarouselStripLayout.seamWidth`, `EditorToolRail.separatorHeight`) rather
    /// than a `UIScreen.main.scale`-derived value. `UIScreen.main` is deprecated
    /// as of iOS 26 and would misreport the scale on an external display anyway.
    private static let separatorHeight: CGFloat = 1

    private let titleLabel = UILabel()
    private let closeButton = UIButton(type: .system)
    private let contentContainer = UIView()
    private var content: UIView?

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surfaceRaised
        isHidden = true
        setupSubviews()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setupSubviews() {
        let separator = UIView()
        separator.backgroundColor = Theme.Color.separator
        separator.translatesAutoresizingMaskIntoConstraints = false
        addSubview(separator)

        titleLabel.font = Theme.Typography.tabLabel
        titleLabel.textColor = Theme.Color.textSecondary
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        addSubview(titleLabel)

        closeButton.setImage(UIImage(systemName: "xmark"), for: .normal)
        closeButton.tintColor = Theme.Color.textSecondary
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

            titleLabel.topAnchor.constraint(equalTo: topAnchor, constant: Theme.Spacing.xs),
            titleLabel.leadingAnchor.constraint(equalTo: leadingAnchor, constant: Theme.Spacing.md),

            // Explicit width/height, not just a center pin: a control sized only
            // by centerX/centerY constraints (with no intrinsic content driving
            // its bounds) resolves to a zero frame — it still draws via its
            // image view, but hit-testing at that point falls through to the
            // panel underneath. See EditorToolRail.ToolButton's regression test
            // for the same trap on a bare UIControl.
            closeButton.centerYAnchor.constraint(equalTo: titleLabel.centerYAnchor),
            closeButton.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -Theme.Spacing.md),
            closeButton.widthAnchor.constraint(equalToConstant: 28),
            closeButton.heightAnchor.constraint(equalToConstant: 28),

            contentContainer.topAnchor.constraint(equalTo: titleLabel.bottomAnchor,
                                                  constant: Theme.Spacing.xs),
            contentContainer.leadingAnchor.constraint(equalTo: leadingAnchor),
            contentContainer.trailingAnchor.constraint(equalTo: trailingAnchor),
            contentContainer.bottomAnchor.constraint(equalTo: bottomAnchor,
                                                     constant: -Theme.Spacing.xs),
        ])
    }

    // MARK: - Presentation

    public func show(_ view: UIView, title: String, animated: Bool) {
        content?.removeFromSuperview()
        content = view

        titleLabel.text = title.uppercased()
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
        isPresenting = false
        currentTitle = nil
        setVisible(false, animated: animated) { [weak self] in
            self?.content?.removeFromSuperview()
            self?.content = nil
        }
    }

    private func setVisible(_ visible: Bool, animated: Bool, completion: (() -> Void)? = nil) {
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
}
