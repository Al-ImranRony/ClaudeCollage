//
//  StickerOverlayView.swift
//  Caroullage
//
//  The live sticker on a canvas (Step 03a slice 6). Split out of CanvasView.swift;
//  the video canvas uses it too.
//

import UIKit

// MARK: - Sticker overlay view

/// One sticker on the canvas: a tinted SF Symbol (drawn via `StickerRendering`, so
/// the live view matches the export) that the user can drag, pinch, rotate, and
/// double-tap to delete. Unlike text, stickers are freely positioned, so each view
/// owns its gestures and reports normalized geometry back through closures.
final class StickerOverlayView: UIView {

    let stickerID: UUID
    private var overlay: StickerOverlay
    /// Resolved bitmap for a personal sticker; nil for a symbol sticker.
    private var source: CGImage?
    private let imageView = UIImageView()
    private let selectionLayer = CAShapeLayer()

    /// Points-per-container-point that normalization divides by — the superview
    /// (the canvas content container) is the reference frame.
    private var containerSize: CGSize { superview?.bounds.size ?? bounds.size }

    var onChanged: ((StickerOverlay) -> Void)?
    var onCommitted: (() -> Void)?
    var onDeleted: ((UUID) -> Void)?
    var onSelected: ((UUID) -> Void)?
    /// Reports the engaged snap guides (normalized x's, y's) so the canvas can draw
    /// them; an empty pair clears them.
    var onGuidesChanged: (([CGFloat], [CGFloat]) -> Void)?

    private var wasSnapped = false
    /// The finger's true (unsnapped) centre during a drag; snapping is layered on
    /// top of this as a display magnet so the sticker never feels stuck to a guide.
    private var dragRawCenter: CGPoint = .zero

    var isSelected: Bool = false {
        didSet {
            selectionLayer.isHidden = !isSelected
            refreshAccessibility()
        }
    }

    init(overlay: StickerOverlay) {
        self.stickerID = overlay.id
        self.overlay = overlay
        super.init(frame: .zero)

        backgroundColor = .clear
        imageView.contentMode = .scaleAspectFit
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = Theme.Color.accent.cgColor
        selectionLayer.lineDashPattern = [5, 4]
        selectionLayer.lineWidth = 1.5
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        installGestures()
        refreshAccessibility()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Accessibility (phase 6.5)

    /// Every gesture, as an action: pinch (×1.1 / ÷1.1), rotate (±15°), drag
    /// (2% of the canvas) and the double-tap delete. Each one ends the way the
    /// gesture ends — geometry applied, `onChanged`, then one `onCommitted`.
    static let scaleStep: Double = 1.1
    static let rotationStep: Double = .pi / 12
    static let nudgeStep: Double = 0.02
    /// The pinch gesture's clamp, as fractions of the container width.
    static let sizeRange: ClosedRange<Double> = 0.06...1.6

    private func refreshAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = CanvasAccessibility.stickerLabel(
            name: CanvasAccessibility.stickerName(fromID: overlay.stickerID),
            isPersonal: overlay.imageID != nil)
        accessibilityHint = CanvasAccessibility.stickerHint
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        accessibilityCustomActions = [
            UIAccessibilityCustomAction(name: CanvasAccessibility.deleteAction) { [weak self] _ in
                guard let self else { return false }
                self.onDeleted?(self.stickerID)
                return true
            },
            action(CanvasAccessibility.largerAction) {
                $0.sizeNorm = min(Self.sizeRange.upperBound, $0.sizeNorm * Self.scaleStep)
            },
            action(CanvasAccessibility.smallerAction) {
                $0.sizeNorm = max(Self.sizeRange.lowerBound, $0.sizeNorm / Self.scaleStep)
            },
            action(CanvasAccessibility.rotateLeftAction) { $0.rotation -= Self.rotationStep },
            action(CanvasAccessibility.rotateRightAction) { $0.rotation += Self.rotationStep },
            action(CanvasAccessibility.moveUpAction) { $0.centerY -= Self.nudgeStep },
            action(CanvasAccessibility.moveDownAction) { $0.centerY += Self.nudgeStep },
            action(CanvasAccessibility.moveLeftAction) { $0.centerX -= Self.nudgeStep },
            action(CanvasAccessibility.moveRightAction) { $0.centerX += Self.nudgeStep },
        ]
    }

    private func action(_ name: String,
                        _ mutate: @escaping (inout StickerOverlay) -> Void) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: name) { [weak self] _ in
            guard let self else { return false }
            var updated = self.overlay
            mutate(&updated)
            self.apply(overlay: updated, in: self.containerSize, source: self.source)
            self.onChanged?(updated)
            self.onCommitted?()
            return true
        }
    }

    override func accessibilityActivate() -> Bool {
        select()
        return true
    }

    /// Positions the view from its normalized model at the given container size and
    /// re-renders the symbol crisply at the resolved point side.
    func apply(overlay: StickerOverlay, in containerSize: CGSize, source: CGImage? = nil) {
        self.overlay = overlay
        self.source = source
        let side = max(8, CGFloat(overlay.sizeNorm) * containerSize.width)
        // Set bounds with an identity transform, then re-apply the rotation, so the
        // rotation composes cleanly with the new size (mirrors CellContentView).
        transform = .identity
        bounds = CGRect(x: 0, y: 0, width: side, height: side)
        center = CGPoint(x: CGFloat(overlay.centerX) * containerSize.width,
                         y: CGFloat(overlay.centerY) * containerSize.height)
        transform = CGAffineTransform(rotationAngle: CGFloat(overlay.rotation))
        refreshImage(side: side)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        imageView.frame = bounds
        selectionLayer.frame = bounds
        selectionLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 6
        ).cgPath
    }

    private func refreshImage(side: CGFloat) {
        imageView.image = StickerRendering.image(for: overlay, sidePx: side, source: source)
    }

    // MARK: - Gestures

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        let doubleTap = UITapGestureRecognizer(target: self, action: #selector(handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        tap.require(toFail: doubleTap)
        for recognizer in [pan, pinch, rotate, tap, doubleTap] as [UIGestureRecognizer] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
        isUserInteractionEnabled = true
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = superview else { return }
        switch gesture.state {
        case .began:
            select()
            dragRawCenter = center
        case .changed:
            let translation = gesture.translation(in: container)
            gesture.setTranslation(.zero, in: container)
            // Track the finger's true (unsnapped) position; the snap is applied as a
            // pure display magnet on top of it, so the sticker never sticks — once the
            // finger moves past the threshold the view follows it immediately.
            dragRawCenter.x += translation.x
            dragRawCenter.y += translation.y
            center = snappedCenter(for: dragRawCenter, in: container.bounds.size)
            emitChange()
        case .ended, .cancelled, .failed:
            wasSnapped = false
            onGuidesChanged?([], [])
            onCommitted?()
        default:
            break
        }
    }

    /// Snaps a raw (unsnapped) centre to alignment guides (canvas centre + thirds)
    /// and returns the centre to display, reporting which guides engaged with a light
    /// tick the moment one grabs.
    private func snappedCenter(for raw: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return raw }
        let normalized = CGPoint(x: raw.x / size.width, y: raw.y / size.height)
        let snap = SnapEngine.snap(center: normalized)
        if snap.didSnap, !wasSnapped { Haptics.boundary() }
        wasSnapped = snap.didSnap
        onGuidesChanged?(snap.verticalGuides, snap.horizontalGuides)
        return CGPoint(x: snap.center.x * size.width, y: snap.center.y * size.height)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let container = superview else { return }
        switch gesture.state {
        case .began:
            select()
        case .changed:
            let minSide = container.bounds.width * 0.06
            let maxSide = container.bounds.width * 1.6
            let newSide = min(max(bounds.width * gesture.scale, minSide), maxSide)
            gesture.scale = 1
            bounds = CGRect(x: 0, y: 0, width: newSide, height: newSide)
            emitChange()
        case .ended, .cancelled, .failed:
            refreshImage(side: bounds.width)   // re-render crisply at the final size
            onCommitted?()
        default:
            break
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        switch gesture.state {
        case .began:
            select()
        case .changed:
            transform = transform.rotated(by: gesture.rotation)
            gesture.rotation = 0
            emitChange()
        case .ended, .cancelled, .failed:
            onCommitted?()
        default:
            break
        }
    }

    @objc private func handleTap() {
        select()
    }

    @objc private func handleDoubleTap() {
        Haptics.warning()
        onDeleted?(stickerID)
    }

    private func select() {
        if !isSelected { onSelected?(stickerID) }
    }

    /// Reports the view's current geometry back as a normalized overlay.
    private func emitChange() {
        let size = containerSize
        guard size.width > 0, size.height > 0 else { return }
        var updated = overlay
        updated.centerX = Double(center.x / size.width)
        updated.centerY = Double(center.y / size.height)
        updated.sizeNorm = Double(bounds.width / size.width)
        updated.rotation = Double(atan2(transform.b, transform.a))
        overlay = updated
        onChanged?(updated)
    }
}

extension StickerOverlayView: UIGestureRecognizerDelegate {
    // Move + pinch + rotate must compose on the same sticker simultaneously.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
