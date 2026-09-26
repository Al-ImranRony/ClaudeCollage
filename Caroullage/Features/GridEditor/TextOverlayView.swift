//
//  TextOverlayView.swift
//  Caroullage
//
//  The live text zone on a canvas (Step 03a slice 5). Split out of CanvasView.swift;
//  the video canvas uses it too.
//

import UIKit

// MARK: - Text overlay view

/// One text zone on the canvas. A vertically-centring UILabel that renders the
/// exact attributed string `TextRendering` produces, so the live preview matches
/// the Core Graphics export. Interactive: a pan drags it around the canvas (with
/// the same alignment snapping as stickers) and a tap opens its styling sheet.
final class TextOverlayView: UIView {

    private let label = UILabel()
    /// `.pill`'s background, painted BEHIND the label. `.highlight` needs no such
    /// layer — it rides `.backgroundColor` inside the label's attributed string
    /// (see `TextRendering.applyStyle`), so it already matches the export.
    private let backgroundLayer = CALayer()
    private let selectionLayer = CAShapeLayer()

    /// The overlay this view currently renders — set on `configure` and mutated as
    /// the view drags itself, so its emitted geometry always carries the right id.
    private var overlay: TextOverlay?
    /// The id of the overlay this view currently renders, for the canvas's
    /// identity-based selection lookup (mirrors `StickerOverlayView.stickerID`,
    /// which is a stored `let` — this can't be, since a pooled view's overlay
    /// changes identity across a rebuild).
    var overlayID: UUID? { overlay?.id }
    /// Stashed from the last `configure` so a bounds-only change (rotation, layout
    /// pass) can still re-derive the background rect without a fresh `configure`.
    private var fontScale: CGFloat = 1

    /// The finger's true (unsnapped) centre during a drag; snapping is layered on
    /// top of this as a display magnet so the zone never feels "stuck" to a guide.
    private var dragRawCenter: CGPoint = .zero
    private var wasSnapped = false

    var onChanged: ((TextOverlay) -> Void)?
    var onCommitted: (() -> Void)?
    var onTapped: ((UUID) -> Void)?
    /// Reports the engaged snap guides (normalized x's, y's); an empty pair clears them.
    var onGuidesChanged: (([CGFloat], [CGFloat]) -> Void)?

    /// Persistent selection state, driven by the view controller's
    /// `selectedTextID` via `CanvasView.setSelectedTextOverlay` — mirrors
    /// `StickerOverlayView.isSelected`, so a selected text zone reads on the
    /// canvas the same way a selected cell or sticker does, rather than relying
    /// on the rail chip as the only feedback.
    var isSelected: Bool = false {
        didSet {
            updateSelectionLayerVisibility()
            refreshAccessibility()
        }
    }

    /// Live drag also shows the selection outline (as it always has); the two
    /// states are independent inputs to the same chrome; the layer is visible
    /// whenever either is true.
    private var isDragging: Bool = false {
        didSet { updateSelectionLayerVisibility() }
    }

    private func updateSelectionLayerVisibility() {
        selectionLayer.isHidden = !(isSelected || isDragging)
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        clipsToBounds = true

        backgroundLayer.isHidden = true
        layer.addSublayer(backgroundLayer)

        label.numberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        addSubview(label)

        selectionLayer.fillColor = UIColor.clear.cgColor
        selectionLayer.strokeColor = Theme.Color.accent.cgColor
        selectionLayer.lineDashPattern = [5, 4]
        selectionLayer.lineWidth = 1.5
        selectionLayer.isHidden = true
        layer.addSublayer(selectionLayer)

        installGestures()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with overlay: TextOverlay, fontScale: CGFloat) {
        self.overlay = overlay
        self.fontScale = fontScale
        label.attributedText = TextRendering.attributedString(for: overlay, fontScale: fontScale)
        refreshBackground()
        refreshAccessibility()
    }

    // MARK: - Accessibility (phase 6.5)

    /// A nudge moves the zone by this fraction of the canvas — a keyboard-arrow
    /// step: fine enough to place, coarse enough that placing is not tedious.
    static let nudgeStep: CGFloat = 0.02

    private func refreshAccessibility() {
        isAccessibilityElement = true
        accessibilityLabel = CanvasAccessibility.textLabel(overlay?.text ?? "")
        accessibilityHint = CanvasAccessibility.textHint
        accessibilityTraits = isSelected ? [.button, .selected] : .button
        let moves: [(String, CGVector)] = [
            (CanvasAccessibility.moveUpAction, CGVector(dx: 0, dy: -1)),
            (CanvasAccessibility.moveDownAction, CGVector(dx: 0, dy: 1)),
            (CanvasAccessibility.moveLeftAction, CGVector(dx: -1, dy: 0)),
            (CanvasAccessibility.moveRightAction, CGVector(dx: 1, dy: 0)),
        ]
        accessibilityCustomActions = moves.map { name, direction in
            UIAccessibilityCustomAction(name: name) { [weak self] _ in
                self?.nudge(direction)
                return true
            }
        }
    }

    /// The drag gesture's end state without the drag: move the view, report the
    /// new frame through `onChanged`, then commit one undo snapshot.
    private func nudge(_ direction: CGVector) {
        guard let container = superview else { return }
        let size = container.bounds.size
        center.x += direction.dx * Self.nudgeStep * size.width
        center.y += direction.dy * Self.nudgeStep * size.height
        emitChange(in: size)
        onCommitted?()
    }

    override func accessibilityActivate() -> Bool {
        handleTap()
        return true
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        selectionLayer.frame = bounds
        selectionLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 6
        ).cgPath
        refreshBackground()
    }

    /// Keeps the `.pill` background layer in lockstep with `TextRendering`'s shared
    /// helper — the same geometry the export draws, computed in `bounds`' own
    /// coordinate space (origin zero, matching how `label.frame = bounds` already
    /// works), so the canvas and the export agree by construction.
    private func refreshBackground() {
        guard let overlay else {
            backgroundLayer.isHidden = true
            return
        }
        TextRendering.paintBackground(
            TextRendering.backgroundRect(for: overlay, in: bounds, fontScale: fontScale),
            colorHex: overlay.style.colorHex,
            on: backgroundLayer)
    }

    // MARK: - Gestures

    private func installGestures() {
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap))
        for recognizer in [pan, tap] as [UIGestureRecognizer] {
            recognizer.delegate = self
            addGestureRecognizer(recognizer)
        }
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let container = superview else { return }
        switch gesture.state {
        case .began:
            isDragging = true
            dragRawCenter = center
        case .changed:
            let translation = gesture.translation(in: container)
            gesture.setTranslation(.zero, in: container)
            dragRawCenter.x += translation.x
            dragRawCenter.y += translation.y
            center = snappedCenter(for: dragRawCenter, in: container.bounds.size)
            emitChange(in: container.bounds.size)
        case .ended, .cancelled, .failed:
            isDragging = false
            wasSnapped = false
            onGuidesChanged?([], [])
            onCommitted?()
        default:
            break
        }
    }

    @objc private func handleTap() {
        if let id = overlay?.id { onTapped?(id) }
    }

    /// Snaps a raw (unsnapped) centre to the alignment guides and returns the centre
    /// to display, reporting which guides engaged plus a light tick as one grabs.
    private func snappedCenter(for raw: CGPoint, in size: CGSize) -> CGPoint {
        guard size.width > 0, size.height > 0 else { return raw }
        let normalized = CGPoint(x: raw.x / size.width, y: raw.y / size.height)
        let snap = SnapEngine.snap(center: normalized)
        if snap.didSnap, !wasSnapped { Haptics.boundary() }
        wasSnapped = snap.didSnap
        onGuidesChanged?(snap.verticalGuides, snap.horizontalGuides)
        return CGPoint(x: snap.center.x * size.width, y: snap.center.y * size.height)
    }

    /// Reports the view's current centre back as a normalized overlay (origin =
    /// centre − half the normalized size), leaving size/style untouched.
    private func emitChange(in size: CGSize) {
        guard var updated = overlay, size.width > 0, size.height > 0 else { return }
        updated.frameX = Double(center.x / size.width) - updated.frameWidth / 2
        updated.frameY = Double(center.y / size.height) - updated.frameHeight / 2
        overlay = updated
        onChanged?(updated)
    }
}

extension TextOverlayView: UIGestureRecognizerDelegate {
    // Let the drag coexist with the canvas recognizers rather than cancelling them
    // (the editor's cell pan already treats a touch on a text zone as inert).
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
