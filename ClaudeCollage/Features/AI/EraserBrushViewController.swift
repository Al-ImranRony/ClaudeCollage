//
//  EraserBrushViewController.swift
//  ClaudeCollage
//
//  Step 05 batch B — the magic eraser's brush surface.
//
//  UIKit, per the brief: brush precision is the whole interaction, and a
//  UIPanGestureRecognizer over a CAShapeLayer gives exact touch tracking with no
//  layout system in the way.
//
//  A modal sub-editor over ONE cell's photo. Stroke-level undo is local (pop the
//  last stroke and redraw); the collage's own UndoStack sees a single entry for
//  the finished erase, via the existing `setImage(_:forCellAt:)` commit. That is
//  the right split — undoing an erase from the collage should not walk back
//  through individual brush strokes the user already finished with.
//

import AVFoundation
import CoreGraphics
import UIKit

@MainActor
final class EraserBrushViewController: UIViewController {

    /// Called with the erased photo, or nil if the user cancelled.
    var onFinish: ((CGImage?) -> Void)?

    private let sourceImage: CGImage
    private let eraser = ObjectEraser()

    private var strokes: [EraserStroke] = []
    private var currentPoints: [CGPoint] = []

    private let imageView = UIImageView()
    private let paintLayer = CAShapeLayer()
    private let sizeSlider = UISlider()
    private lazy var undoButton = makeUndoButton()

    /// Brush radius as a fraction of the photo's smaller side. The brief asks for
    /// 10–200pt; expressed proportionally so it means the same thing whatever the
    /// photo's resolution.
    private var brushRadius: CGFloat = 0.06
    private static let minRadius: CGFloat = 0.015
    private static let maxRadius: CGFloat = 0.22

    init(image: CGImage) {
        self.sourceImage = image
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "Magic Eraser"
        view.backgroundColor = Theme.Color.background
        setupNavigationBar()
        setupLayout()
        setupGesture()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        paintLayer.frame = imageView.bounds
        redrawPaint()
    }

    // MARK: - Setup

    private func setupNavigationBar() {
        let cancel = UIBarButtonItem(
            title: "Cancel", style: .plain, target: self, action: #selector(cancelTapped))
        cancel.accessibilityIdentifier = "eraserCancelButton"
        let done = UIBarButtonItem(
            title: "Done", style: .done, target: self, action: #selector(doneTapped))
        done.accessibilityIdentifier = "eraserDoneButton"
        navigationItem.leftBarButtonItem = cancel
        navigationItem.rightBarButtonItems = [done, undoButton]
    }

    private func setupLayout() {
        imageView.image = UIImage(cgImage: sourceImage)
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        imageView.accessibilityIdentifier = "eraserCanvas"

        paintLayer.fillColor = UIColor.clear.cgColor
        paintLayer.strokeColor = Theme.Color.accent.withAlphaComponent(0.55).cgColor
        paintLayer.lineCap = .round
        paintLayer.lineJoin = .round
        imageView.layer.addSublayer(paintLayer)

        sizeSlider.minimumValue = Float(Self.minRadius)
        sizeSlider.maximumValue = Float(Self.maxRadius)
        sizeSlider.value = Float(brushRadius)
        sizeSlider.accessibilityIdentifier = "eraserSizeSlider"
        sizeSlider.addTarget(self, action: #selector(sizeChanged), for: .valueChanged)

        let hint = UILabel()
        hint.text = "Paint over what you want gone. Works best on plain backgrounds."
        hint.font = Theme.Typography.caption
        hint.textColor = Theme.Color.textSecondary
        hint.numberOfLines = 0
        hint.textAlignment = .center

        let brushIcon = UIImageView(image: UIImage(systemName: "paintbrush.pointed"))
        brushIcon.tintColor = Theme.Color.textSecondary
        brushIcon.setContentHuggingPriority(.required, for: .horizontal)

        let sliderRow = UIStackView(arrangedSubviews: [brushIcon, sizeSlider])
        sliderRow.axis = .horizontal
        sliderRow.spacing = Theme.Spacing.sm
        sliderRow.alignment = .center

        let controls = UIStackView(arrangedSubviews: [hint, sliderRow])
        controls.axis = .vertical
        controls.spacing = Theme.Spacing.sm
        controls.isLayoutMarginsRelativeArrangement = true
        controls.layoutMargins = UIEdgeInsets(
            top: 0, left: Theme.Spacing.md, bottom: 0, right: Theme.Spacing.md)
        controls.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(imageView)
        view.addSubview(controls)
        NSLayoutConstraint.activate([
            imageView.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: view.trailingAnchor),

            controls.topAnchor.constraint(equalTo: imageView.bottomAnchor, constant: Theme.Spacing.md),
            controls.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            controls.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            controls.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.lg),
        ])
        updateUndoState()
    }

    private func setupGesture() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.maximumNumberOfTouches = 1
        imageView.addGestureRecognizer(pan)
        // A tap is a legitimate dab of paint, not just a drag.
        imageView.addGestureRecognizer(
            UITapGestureRecognizer(target: self, action: #selector(handleTap)))
    }

    private func makeUndoButton() -> UIBarButtonItem {
        let item = UIBarButtonItem(
            image: UIImage(systemName: "arrow.uturn.backward"),
            style: .plain, target: self, action: #selector(undoStroke))
        item.accessibilityIdentifier = "eraserUndoButton"
        item.accessibilityLabel = "Undo stroke"
        return item
    }

    // MARK: - Painting

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        let point = gesture.location(in: imageView)
        switch gesture.state {
        case .began:
            currentPoints = [point]
        case .changed:
            currentPoints.append(point)
            redrawPaint()
        case .ended, .cancelled, .failed:
            commitCurrentStroke()
        default:
            break
        }
    }

    @objc private func handleTap(_ gesture: UITapGestureRecognizer) {
        currentPoints = [gesture.location(in: imageView)]
        commitCurrentStroke()
    }

    private func commitCurrentStroke() {
        defer { currentPoints = [] }
        guard !currentPoints.isEmpty else { return }
        let normalized = currentPoints.compactMap(normalizedPoint)
        guard !normalized.isEmpty else { return }   // entirely in the letterbox
        strokes.append(EraserStroke(points: normalized, radius: brushRadius))
        Haptics.tap()
        redrawPaint()
        updateUndoState()
    }

    @objc private func undoStroke() {
        guard !strokes.isEmpty else { return }
        strokes.removeLast()
        Haptics.selectionChanged()
        redrawPaint()
        updateUndoState()
    }

    private func updateUndoState() {
        undoButton.isEnabled = !strokes.isEmpty
    }

    @objc private func sizeChanged() {
        brushRadius = CGFloat(sizeSlider.value)
        redrawPaint()
    }

    // MARK: - Coordinates

    /// The photo's on-screen rect inside the aspect-fit image view. Everything
    /// outside it is letterbox, not photo.
    private var displayedImageRect: CGRect {
        AVMakeRect(
            aspectRatio: CGSize(width: sourceImage.width, height: sourceImage.height),
            insideRect: imageView.bounds)
    }

    /// View point → normalized image point (top-left origin), or nil if the touch
    /// landed on the letterbox rather than the photo.
    private func normalizedPoint(_ point: CGPoint) -> CGPoint? {
        let rect = displayedImageRect
        guard rect.width > 0, rect.height > 0, rect.contains(point) else { return nil }
        return CGPoint(x: (point.x - rect.minX) / rect.width,
                       y: (point.y - rect.minY) / rect.height)
    }

    /// Redraws the live paint preview, including the in-progress stroke.
    private func redrawPaint() {
        let rect = displayedImageRect
        guard rect.width > 0 else { return }

        let path = UIBezierPath()
        for stroke in strokes {
            append(stroke.points.map { CGPoint(x: rect.minX + $0.x * rect.width,
                                               y: rect.minY + $0.y * rect.height) }, to: path)
        }
        append(currentPoints, to: path)

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        // Matches the mask: radius is a fraction of the photo's smaller side.
        paintLayer.lineWidth = brushRadius * min(rect.width, rect.height) * 2
        paintLayer.path = path.cgPath
        CATransaction.commit()
    }

    private func append(_ points: [CGPoint], to path: UIBezierPath) {
        guard let first = points.first else { return }
        if points.count == 1 {
            // Drawn as a zero-length segment so the round cap renders the dab.
            path.move(to: first)
            path.addLine(to: first)
            return
        }
        path.move(to: first)
        for point in points.dropFirst() { path.addLine(to: point) }
    }

    // MARK: - Finishing

    @objc private func cancelTapped() {
        onFinish?(nil)
    }

    @objc private func doneTapped() {
        guard !strokes.isEmpty else {
            onFinish?(nil)      // nothing painted — same as cancelling
            return
        }
        guard let erased = eraser.erase(sourceImage, strokes: strokes) else {
            Haptics.error()
            let alert = UIAlertController(
                title: "Magic Eraser",
                message: "Couldn't erase that area. Try painting over it again.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        Haptics.success()
        onFinish?(erased)
    }
}
