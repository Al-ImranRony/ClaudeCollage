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
//  It now wears `QuickStartTile` rows. Those were lifted into the component
//  layer so this sheet and Home's "Create New" could be cut from one part — the
//  two surfaces offer overlapping choices and should not look like unrelated
//  features. Step 07 rebuilt Home as a showcase and shrank its copy to the
//  private `QuickStartChip`, so this sheet is the tile's only caller now and
//  the overlap survives as a convention between two screens rather than as
//  shared code.
//
//  The accessibility identifiers are unchanged from the action-sheet version, so
//  the existing shell tests keep working; only their `app.sheets` qualifier had
//  to go, since that matches a UIAlertController specifically.
//
//  Step 06 re-cut the menu onto one axis — what are you making? — because it had
//  drifted into two: Camera and Photos are where the pictures come from and land
//  in the same collage, while Video and Custom Canvas are formats. Carousel
//  joined them; until then the app's global create button offered everything
//  except the app's signature format, which is why the Carousel tab was carrying
//  a create form of its own.
//

import UIKit

@MainActor
final class StartEditingSheetViewController: UIViewController {

    private let onCamera: () -> Void
    private let onImage: () -> Void
    private let onVideo: () -> Void
    private let onCarousel: () -> Void
    private let onCustomCanvas: () -> Void

    init(
        onCamera: @escaping () -> Void,
        onImage: @escaping () -> Void,
        onVideo: @escaping () -> Void,
        onCarousel: @escaping () -> Void,
        onCustomCanvas: @escaping () -> Void
    ) {
        self.onCamera = onCamera
        self.onImage = onImage
        self.onVideo = onVideo
        self.onCarousel = onCarousel
        self.onCustomCanvas = onCustomCanvas
        super.init(nibName: nil, bundle: nil)

        modalPresentationStyle = .pageSheet
        if let sheet = sheetPresentationController {
            // A content-sized detent rather than `.medium()`: the rows do not
            // fill half the screen, and a half-height sheet with a third of it
            // empty reads as something failing to load.
            sheet.detents = [.custom(identifier: .init("startEditing")) { [weak self] context in
                Self.detentHeight(
                    measured: self?.measuredContentHeight ?? 0,
                    maximum: context.maximumDetentValue)
            }]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Used until the rows have been laid out and can be measured. The detent
    /// resolver runs before the first layout pass, and returning 0 there opens a
    /// zero-height sheet.
    static let fallbackHeight: CGFloat = 420

    /// What the custom detent resolves to.
    ///
    /// This used to be a bare constant, and it had already drifted: the comment
    /// said three rows while four were rendered. A fifth row broke it outright.
    /// Measuring instead means the sheet is sized by what is in it, at whatever
    /// text size the user has chosen — and clamping means a tall measurement on a
    /// small phone cannot produce a detent UIKit rejects.
    static func detentHeight(measured: CGFloat, maximum: CGFloat) -> CGFloat {
        min(measured > 0 ? measured : fallbackHeight, maximum)
    }

    /// The title-plus-rows stack, held so the detent can measure it.
    private let contentStack = UIStackView()
    /// Guards `invalidateDetents` against re-entering its own layout pass.
    private var lastMeasuredHeight: CGFloat = 0

    /// What the content actually needs, once it has a width to lay out in.
    /// Zero before the first layout pass, which `detentHeight` reads as "no
    /// measurement yet".
    private var measuredContentHeight: CGFloat {
        let width = contentStack.bounds.width
        guard width > 0 else { return 0 }
        let fitting = contentStack.systemLayoutSizeFitting(
            CGSize(width: width, height: 0),
            withHorizontalFittingPriority: .required,
            verticalFittingPriority: .fittingSizeLevel)
        // The stack is pinned `xl` from the top and has no bottom constraint, so
        // the trailing margin and the home indicator have to be added back.
        return fitting.height + Theme.Spacing.xl + Theme.Spacing.lg + view.safeAreaInsets.bottom
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Re-resolves the detent once the rows have a real size — and again if the
        // user changes text size while the sheet is open. Measuring depends on
        // width, not on the height this call changes, so it settles in one round.
        let height = measuredContentHeight
        guard abs(height - lastMeasuredHeight) > 0.5 else { return }
        lastMeasuredHeight = height
        sheetPresentationController?.invalidateDetents()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = Theme.Color.background
        view.accessibilityIdentifier = "startEditingSheet"

        let title = UILabel()
        // The same words as Home's chip row: the two surfaces offer the same
        // four doors and should not name them differently.
        title.text = String(localized: "Create New")
        title.font = Theme.Typography.title2
        title.textColor = Theme.Color.textPrimary
        title.adjustsFontForContentSizeCategory = true

        let rows = [
            // Camera first: it is the only row that makes something that does not
            // exist yet, and it is the reason to open the app in the moment.
            QuickStartTile(
                title: "Camera", subtitle: "Shoot one now, with a filter",
                symbol: "camera.fill", identifier: "startEditingCamera"
            ) { [weak self] in self?.finish(self?.onCamera) },
            // "Photos", not "Image": every other row names an activity, and this
            // one named a file format. The identifier stays `startEditingImage`
            // for the same reason it survived the move off UIAlertController —
            // renaming it buys nothing and costs every test that keys on it.
            QuickStartTile(
                title: "Photos", subtitle: "Pick photos, we'll fit a layout",
                symbol: "photo.on.rectangle.angled", identifier: "startEditingImage"
            ) { [weak self] in self?.finish(self?.onImage) },
            QuickStartTile(
                title: "Video", subtitle: "A moving collage", symbol: "play.rectangle.fill",
                identifier: "startEditingVideo"
            ) { [weak self] in self?.finish(self?.onVideo) },
            // Next to Video because both are multi-frame outputs. Its glyph is the
            // one the gallery badges a carousel card with, so the offer and the
            // result are visibly the same thing.
            QuickStartTile(
                title: "Carousel", subtitle: "A multi-frame post for the feed",
                symbol: CollageMode.carousel.badgeSymbolName,
                identifier: "startEditingCarousel"
            ) { [weak self] in self?.finish(self?.onCarousel) },
            QuickStartTile(
                title: "Custom Canvas", subtitle: "Choose your own size",
                symbol: "square.resize", identifier: "startEditingCustomCanvas"
            ) { [weak self] in self?.finish(self?.onCustomCanvas) },
        ]

        ([title] + rows).forEach(contentStack.addArrangedSubview)
        contentStack.axis = .vertical
        contentStack.spacing = Theme.Spacing.sm
        contentStack.setCustomSpacing(Theme.Spacing.lg, after: title)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(contentStack)

        NSLayoutConstraint.activate([
            contentStack.topAnchor.constraint(
                equalTo: view.topAnchor, constant: Theme.Spacing.xl),
            contentStack.leadingAnchor.constraint(
                equalTo: view.leadingAnchor, constant: Theme.Spacing.md),
            contentStack.trailingAnchor.constraint(
                equalTo: view.trailingAnchor, constant: -Theme.Spacing.md),
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
