//
//  StartEditingSheetViewController.swift
//  Caroullage
//
//  Step 05b Part C — the new-project entry.
//
//  The floating "+" used to open a stock `UIAlertController` action sheet: three
//  lines of blue system text, in an app whose every other surface had been
//  themed. It is the most-tapped control in the shell and it looked like a
//  debug menu.
//
//  It now wears the same `QuickStartTile` rows as Home's "Start Something",
//  which is the whole reason that row was lifted into the component layer — the
//  two surfaces offer overlapping choices and should not look like unrelated
//  features.
//
//  The accessibility identifiers are unchanged from the action-sheet version, so
//  the existing shell tests keep working; only their `app.sheets` qualifier had
//  to go, since that matches a UIAlertController specifically.
//

import UIKit

@MainActor
final class StartEditingSheetViewController: UIViewController {

    private let onImage: () -> Void
    private let onVideo: () -> Void
    private let onCustomCanvas: () -> Void

    init(
        onImage: @escaping () -> Void,
        onVideo: @escaping () -> Void,
        onCustomCanvas: @escaping () -> Void
    ) {
        self.onImage = onImage
        self.onVideo = onVideo
        self.onCustomCanvas = onCustomCanvas
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // A content-sized detent rather than `.medium()`: three rows do not
            // fill half the screen, and a half-height sheet with a third of it
            // empty reads as something failing to load.
            sheet.detents = [.custom(identifier: .init("startEditing")) { _ in Self.contentHeight }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Title + three rows + margins. Kept as a constant because the detent has to
    /// be known before the view exists.
    private static let contentHeight: CGFloat = 336

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        view.accessibilityIdentifier = "startEditingSheet"

        let title = UILabel()
        title.text = "Start Something"
        title.font = Theme.Typography.title2
        title.textColor = Theme.Color.textPrimary
        title.adjustsFontForContentSizeCategory = true

        let rows = [
            QuickStartTile(
                title: "Image", subtitle: "Pick photos, we'll fit a layout",
                symbol: "photo.on.rectangle.angled", identifier: "startEditingImage"
            ) { [weak self] in self?.finish(self?.onImage) },
            QuickStartTile(
                title: "Video", subtitle: "A moving collage", symbol: "play.rectangle.fill",
                identifier: "startEditingVideo"
            ) { [weak self] in self?.finish(self?.onVideo) },
            QuickStartTile(
                title: "Custom Canvas", subtitle: "Choose your own size",
                symbol: "square.resize", identifier: "startEditingCustomCanvas"
            ) { [weak self] in self?.finish(self?.onCustomCanvas) },
        ]

        let stack = UIStackView(arrangedSubviews: [title] + rows)
        stack.axis = .vertical
        stack.spacing = Theme.Spacing.sm
        stack.setCustomSpacing(Theme.Spacing.lg, after: title)
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: view.topAnchor, constant: Theme.Spacing.xl),
            stack.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            stack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),
        ])
    }

    /// Dismisses first, then acts.
    ///
    /// The other order leaves the sheet on screen while a photo picker or an
    /// alert tries to present from a controller that is already covered, which
    /// UIKit answers by dropping the presentation entirely.
    private func finish(_ action: (() -> Void)?) {
        dismiss(animated: true) { action?() }
    }
}
