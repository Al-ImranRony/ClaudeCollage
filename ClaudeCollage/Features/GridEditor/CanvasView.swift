//
//  CanvasView.swift
//  ClaudeCollage
//
//  Step 01 (perf) — GPU-composited canvas.
//
//  Instead of recompositing the whole canvas on the CPU every gesture frame,
//  each cell is its own clipped UIView holding a UIImageView. Pan/zoom/rotate
//  is applied as a CGAffineTransform on that image view, so Core Animation
//  composites it on the GPU — smooth at 60fps with zero per-frame CPU work.
//
//  The Core Graphics compositor (CollageRenderer) is used only for the one-shot
//  export and thumbnail paths. In Step 02 the cell layer can gain a CAShapeLayer
//  mask for polygon clipping without changing this view's public surface.
//

import UIKit
import AVFoundation

/// One cell's display inputs, in reference-canvas pixels.
struct CanvasCellModel {
    let image: CGImage?
    let frame: CGRect          // reference-canvas px (engine output, incl. border)
    var transform: CellTransform
    let cornerRadius: CGFloat  // reference-canvas px
    var clipShape: CellClipShape = .rectangle
}

/// The full canvas display model.
struct CanvasModel {
    let canvasSize: CGSize     // reference px (e.g. 1080×1080)
    let background: CollageBackground
    var cells: [CanvasCellModel]
    /// Text zones layered above the cells (normalized frames). Step 03a slice 5.
    var textOverlays: [TextOverlay] = []
    /// Sticker overlays layered above the text (normalized). Step 03a slice 6.
    var stickerOverlays: [StickerOverlay] = []
}

final class CanvasView: UIView {

    /// The aspect-fit square the collage is drawn inside. Its background colour
    /// shows through the gaps between cells.
    private let contentContainer = UIView()
    private var cellViews: [CellContentView] = []
    /// Text zones, layered above the cells. Kept in a separate view array so text
    /// edits never rebuild the (heavier) photo cell views.
    private var overlayViews: [TextOverlayView] = []
    /// Sticker overlays, layered above the text. Interactive (each owns its
    /// move/resize/rotate/delete gestures), unlike the non-interactive cells/text
    /// which the view controller hit-tests.
    private var stickerViews: [StickerOverlayView] = []
    private var selectedStickerID: UUID?
    private var model: CanvasModel?

    // MARK: - Sticker callbacks (wired by the view controller)

    /// A sticker moved/resized/rotated mid-gesture (live, no undo snapshot yet).
    var onStickerChanged: ((StickerOverlay) -> Void)?
    /// A sticker gesture finished — record one undo snapshot.
    var onStickerCommitted: (() -> Void)?
    /// A sticker was double-tapped to delete.
    var onStickerDeleted: ((UUID) -> Void)?
    /// A sticker was tapped (selected), or `nil` when selection was cleared.
    var onStickerSelected: ((UUID?) -> Void)?

    // MARK: - Text callbacks (wired by the view controller)

    /// A text zone was dragged mid-gesture (live, no undo snapshot yet).
    var onTextChanged: ((TextOverlay) -> Void)?
    /// A text drag finished — record one undo snapshot.
    var onTextCommitted: (() -> Void)?
    /// A text zone was tapped — open its styling sheet.
    var onTextTapped: ((UUID) -> Void)?

    /// On-screen points per reference point (contentContainer.width / canvasSize.width).
    private(set) var referenceScaleFactor: CGFloat = 1

    /// Snap-alignment guide lines drawn above everything during a sticker drag.
    private let snapGuideLayer = CAShapeLayer()

    /// Outline around the selected photo cell. Deliberately mirrors the text and
    /// sticker selection chrome (dashed accent stroke) so all three object types
    /// read as the same kind of "selected".
    ///
    /// Lives on `contentContainer` rather than inside the cell view because cells
    /// clip to bounds and non-rectangular ones carry a `CAShapeLayer` mask — a
    /// stroke drawn inside would be half-clipped away at the very edge it needs
    /// to trace.
    private let cellSelectionLayer = CAShapeLayer()
    private var selectedCellIndex: Int?

    /// Detail-editing magnification of the collage content (1…3). A view aid only —
    /// not part of the collage state, so it never persists or exports.
    private(set) var canvasZoom: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentContainer.clipsToBounds = false
        addSubview(contentContainer)

        snapGuideLayer.strokeColor = Theme.Color.accent.cgColor
        snapGuideLayer.lineWidth = 1
        snapGuideLayer.lineDashPattern = [4, 4]
        snapGuideLayer.fillColor = UIColor.clear.cgColor
        snapGuideLayer.zPosition = 10_000    // above cells, text, and stickers
        snapGuideLayer.isHidden = true
        contentContainer.layer.addSublayer(snapGuideLayer)

        cellSelectionLayer.strokeColor = Theme.Color.accent.cgColor
        cellSelectionLayer.lineWidth = 1.5
        cellSelectionLayer.lineDashPattern = [5, 4]
        cellSelectionLayer.fillColor = UIColor.clear.cgColor
        cellSelectionLayer.zPosition = 9_000     // above content, below snap guides
        cellSelectionLayer.isHidden = true
        contentContainer.layer.addSublayer(cellSelectionLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Configuration

    /// Rebuilds / repositions cell views for a discrete change (layout, border,
    /// background, photo add/clear, undo). NOT called during gestures.
    func configure(with model: CanvasModel) {
        let countChanged = model.cells.count != cellViews.count
        self.model = model

        // A layout change can leave the selection pointing past the new cell list.
        if let selected = selectedCellIndex, selected >= model.cells.count {
            selectedCellIndex = nil
        }

        if countChanged {
            cellViews.forEach { $0.removeFromSuperview() }
            cellViews = model.cells.map { _ in
                let view = CellContentView()
                contentContainer.addSubview(view)
                return view
            }
        }
        // Content (images) is set only here — never in the per-frame layout pass.
        for (index, cell) in model.cells.enumerated() where cellViews.indices.contains(index) {
            cellViews[index].setImage(cell.image)
            cellViews[index].setClipShape(cell.clipShape)
        }
        rebuildOverlayViewsIfNeeded(count: model.textOverlays.count)
        rebuildStickerViews(model.stickerOverlays)
        layoutCanvas()
    }

    /// Lightweight path for text-only edits (typing / styling): refresh the overlay
    /// views without touching the photo cell views or re-wrapping their CGImages.
    func updateTextOverlays(_ overlays: [TextOverlay]) {
        model?.textOverlays = overlays
        rebuildOverlayViewsIfNeeded(count: overlays.count)
        // Keep stickers above the (possibly re-fronted) text views.
        stickerViews.forEach { contentContainer.bringSubviewToFront($0) }
        layoutOverlays()
    }

    /// Lightweight path for sticker add/delete/undo: rebuild the sticker view pool
    /// and reposition, without touching the photo cell or text views.
    func updateStickerOverlays(_ overlays: [StickerOverlay]) {
        model?.stickerOverlays = overlays
        rebuildStickerViews(overlays)
        layoutStickers()
    }

    /// Rebuilds the overlay view pool when the overlay count changes, always
    /// keeping them layered above the photo cells.
    private func rebuildOverlayViewsIfNeeded(count: Int) {
        guard count != overlayViews.count else {
            overlayViews.forEach { contentContainer.bringSubviewToFront($0) }
            return
        }
        overlayViews.forEach { $0.removeFromSuperview() }
        overlayViews = (0..<count).map { _ in
            let view = TextOverlayView()
            view.onChanged = { [weak self] overlay in self?.onTextChanged?(overlay) }
            view.onCommitted = { [weak self] in self?.onTextCommitted?() }
            view.onTapped = { [weak self] id in self?.onTextTapped?(id) }
            view.onGuidesChanged = { [weak self] vx, hy in
                self?.updateSnapGuides(verticalX: vx, horizontalY: hy)
            }
            contentContainer.addSubview(view)
            return view
        }
    }

    /// Rebuilds the interactive sticker view pool from the model, wiring each
    /// view's gesture callbacks back out through this canvas. Always rebuilt (not
    /// pooled by count) because each view is bound to a specific sticker id — cheap,
    /// since stickers are few and light.
    private func rebuildStickerViews(_ overlays: [StickerOverlay]) {
        stickerViews.forEach { $0.removeFromSuperview() }
        stickerViews = overlays.map { overlay in
            let view = StickerOverlayView(overlay: overlay)
            view.onChanged = { [weak self] updated in self?.onStickerChanged?(updated) }
            view.onCommitted = { [weak self] in self?.onStickerCommitted?() }
            view.onDeleted = { [weak self] id in
                if self?.selectedStickerID == id { self?.selectedStickerID = nil }
                self?.onStickerDeleted?(id)
            }
            view.onSelected = { [weak self] id in self?.selectStickerFromTap(id) }
            view.onGuidesChanged = { [weak self] vx, hy in
                self?.updateSnapGuides(verticalX: vx, horizontalY: hy)
            }
            view.isSelected = overlay.id == selectedStickerID
            contentContainer.addSubview(view)
            return view
        }
    }

    /// Fast path: apply one cell's transform during a gesture (GPU only). Keeps
    /// the stored model in sync so a bounds change re-applies it at the new scale.
    func applyTransform(_ transform: CellTransform, toCellAt index: Int) {
        guard cellViews.indices.contains(index) else { return }
        model?.cells[index].transform = transform
        cellViews[index].setGeometryTransform(transform, factor: referenceScaleFactor)
    }

    /// Replaces one cell's image (photo add / filter result) without a full rebuild.
    func setImage(_ image: CGImage?, forCellAt index: Int) {
        guard cellViews.indices.contains(index) else { return }
        cellViews[index].setImage(image)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        layoutCanvas()
    }

    /// Positions cells and re-applies transforms at the current scale. Does NOT
    /// touch cell images, so a bounds change never re-wraps CGImages.
    private func layoutCanvas() {
        guard let model, model.canvasSize.width > 0 else { return }

        // Frame math must run with an identity transform (setting .frame under a
        // non-identity transform is undefined); the zoom transform is re-applied
        // after positioning.
        contentContainer.transform = .identity
        let square = AVMakeRect(aspectRatio: model.canvasSize, insideRect: bounds)
        contentContainer.frame = square
        contentContainer.backgroundColor = UIColor(background: model.background)
        referenceScaleFactor = square.width / model.canvasSize.width
        let factor = referenceScaleFactor

        for (index, cell) in model.cells.enumerated() where cellViews.indices.contains(index) {
            let view = cellViews[index]
            view.frame = CGRect(
                x: cell.frame.minX * factor,
                y: cell.frame.minY * factor,
                width: cell.frame.width * factor,
                height: cell.frame.height * factor
            )
            view.layer.cornerRadius = cell.cornerRadius * factor
            view.setGeometryTransform(cell.transform, factor: factor)
        }

        layoutOverlays()
        layoutStickers()
        updateCellSelection()
        applyZoomTransform()
    }

    // MARK: - Cell selection

    /// Marks one photo cell as selected, or clears the outline with `nil`.
    ///
    /// Preview chrome only: export composites through `CollageRenderer`, which
    /// never sees this view, so the outline cannot be baked into an exported image.
    func setSelectedCell(_ index: Int?) {
        guard index != selectedCellIndex else { return }
        selectedCellIndex = index
        updateCellSelection()
    }

    /// Redraws the selection outline to trace the selected cell's actual boundary,
    /// including its corner radius and any non-rectangular clip shape.
    private func updateCellSelection() {
        guard let model, let index = selectedCellIndex,
              model.cells.indices.contains(index), referenceScaleFactor > 0 else {
            cellSelectionLayer.isHidden = true
            return
        }
        let cell = model.cells[index]
        let factor = referenceScaleFactor
        let scaled = CGRect(
            x: cell.frame.minX * factor,
            y: cell.frame.minY * factor,
            width: cell.frame.width * factor,
            height: cell.frame.height * factor
        )
        // Inset by half the stroke so the dashes sit just inside the cell edge
        // rather than straddling it into the border gap.
        let inset = cellSelectionLayer.lineWidth / 2
        let outline = scaled.insetBy(dx: inset, dy: inset)
        guard outline.width > 0, outline.height > 0 else {
            cellSelectionLayer.isHidden = true
            return
        }

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        cellSelectionLayer.frame = contentContainer.bounds
        cellSelectionLayer.path = cell.clipShape.path(
            in: outline,
            cornerRadius: max(0, cell.cornerRadius * factor - inset)
        )
        cellSelectionLayer.isHidden = false
        CATransaction.commit()
    }

    /// Positions each text overlay view (normalized frame → on-screen points) and
    /// re-renders its attributed text at the current scale. The live font scale is
    /// the same `referenceScaleFactor` used for cell geometry, so on-screen point
    /// sizes track the reference-canvas point sizes that export uses.
    private func layoutOverlays() {
        guard let model else { return }
        let size = contentContainer.bounds.size
        for (index, overlay) in model.textOverlays.enumerated() where overlayViews.indices.contains(index) {
            overlayViews[index].frame = TextRendering.frame(for: overlay, in: size)
            overlayViews[index].configure(with: overlay, fontScale: referenceScaleFactor)
        }
    }

    /// Positions each sticker view from its normalized model at the current
    /// container size. The interactive views mutate their own geometry mid-gesture;
    /// this runs on discrete rebuilds and bounds changes (rotation, resize).
    private func layoutStickers() {
        guard let model else { return }
        let size = contentContainer.bounds.size
        guard size.width > 0 else { return }
        for (index, overlay) in model.stickerOverlays.enumerated() where stickerViews.indices.contains(index) {
            stickerViews[index].apply(overlay: overlay, in: size)
        }
    }

    // MARK: - Snap guides

    /// Draws (or clears) the alignment guide lines at the given normalized
    /// positions, spanning the full collage rect. Called live during a drag.
    func updateSnapGuides(verticalX: [CGFloat], horizontalY: [CGFloat]) {
        let size = contentContainer.bounds.size
        guard size.width > 0, (!verticalX.isEmpty || !horizontalY.isEmpty) else {
            snapGuideLayer.isHidden = true
            return
        }
        let path = UIBezierPath()
        for x in verticalX {
            let px = x * size.width
            path.move(to: CGPoint(x: px, y: 0))
            path.addLine(to: CGPoint(x: px, y: size.height))
        }
        for y in horizontalY {
            let py = y * size.height
            path.move(to: CGPoint(x: 0, y: py))
            path.addLine(to: CGPoint(x: size.width, y: py))
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        snapGuideLayer.frame = contentContainer.bounds
        snapGuideLayer.path = path.cgPath
        snapGuideLayer.isHidden = false
        CATransaction.commit()
    }

    // MARK: - Canvas zoom (detail editing)

    /// Magnifies the collage content around its centre, clamped to 1…3×. A view aid
    /// for detail editing — the collage geometry, state, and export are untouched.
    func setCanvasZoom(_ scale: CGFloat) {
        canvasZoom = min(max(scale, 1), 3)
        applyZoomTransform()
    }

    private func applyZoomTransform() {
        contentContainer.transform = canvasZoom == 1
            ? .identity
            : CGAffineTransform(scaleX: canvasZoom, y: canvasZoom)
    }

    // MARK: - Sticker selection

    /// Marks one sticker selected (or clears selection with `nil`) and updates the
    /// selection chrome on every sticker view. Does not notify the delegate.
    func setSelectedSticker(_ id: UUID?) {
        selectedStickerID = id
        for view in stickerViews { view.isSelected = view.stickerID == id }
    }

    /// Clears any sticker selection and notifies the delegate.
    func deselectSticker() {
        guard selectedStickerID != nil else { return }
        setSelectedSticker(nil)
        onStickerSelected?(nil)
    }

    /// The id of the topmost sticker whose (rotated) view contains `point`
    /// (this view's coordinates), if any.
    func stickerID(at point: CGPoint) -> UUID? {
        let local = convert(point, to: contentContainer)
        for view in stickerViews.reversed() where view.frame.contains(local) {
            return view.stickerID
        }
        return nil
    }

    private func selectStickerFromTap(_ id: UUID) {
        setSelectedSticker(id)
        // Bring the tapped sticker to the front so overlapping stickers cycle.
        if let view = stickerViews.first(where: { $0.stickerID == id }) {
            contentContainer.bringSubviewToFront(view)
        }
        onStickerSelected?(id)
    }

    // MARK: - Hit testing

    /// The on-screen rect occupied by the collage (this view's coordinates).
    var displayedContentRect: CGRect { contentContainer.frame }

    /// Which cell contains `point` (this view's coordinates), if any.
    func cellIndex(at point: CGPoint) -> Int? {
        let local = convert(point, to: contentContainer)
        return cellViews.firstIndex { $0.frame.contains(local) }
    }

    /// The id of the topmost text overlay containing `point` (this view's
    /// coordinates), if any. Text sits above the cells, so the editor tests this
    /// first when a tap lands.
    func overlayID(at point: CGPoint) -> UUID? {
        guard let model else { return nil }
        let local = convert(point, to: contentContainer)
        for (index, overlay) in model.textOverlays.enumerated().reversed()
        where overlayViews.indices.contains(index) && overlayViews[index].frame.contains(local) {
            return overlay.id
        }
        return nil
    }

    /// A cell's on-screen rect (this view's coordinates), for popover anchoring.
    func cellRect(at index: Int) -> CGRect? {
        guard cellViews.indices.contains(index) else { return nil }
        return contentContainer.convert(cellViews[index].frame, to: self)
    }
}

// MARK: - Cell view

/// A single clipped cell that hosts one image view. Pan/zoom/rotate is applied
/// to the image view's transform (GPU); the cell clips overflow natively.
final class CellContentView: UIView {

    private let imageView = UIImageView()
    private let placeholder = UIImageView(image: UIImage(systemName: "plus"))

    /// The cell boundary. `.rectangle` uses the fast layer-cornerRadius path with
    /// no mask; any other shape installs a `CAShapeLayer` mask rebuilt on layout.
    private var clipShape: CellClipShape = .rectangle
    private lazy var shapeMask: CAShapeLayer = {
        let mask = CAShapeLayer()
        mask.fillColor = UIColor.white.cgColor
        return mask
    }()

    override init(frame: CGRect) {
        super.init(frame: frame)
        clipsToBounds = true
        backgroundColor = .secondarySystemBackground

        imageView.contentMode = .scaleAspectFill
        imageView.isUserInteractionEnabled = false
        addSubview(imageView)

        placeholder.tintColor = .tertiaryLabel
        placeholder.contentMode = .scaleAspectFit
        placeholder.isUserInteractionEnabled = false
        addSubview(placeholder)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The image view fills the cell as its transform-neutral baseline; the
        // geometry transform is layered on top of this frame.
        let priorTransform = imageView.transform
        imageView.transform = .identity
        imageView.frame = bounds
        imageView.transform = priorTransform

        let side = min(bounds.width, bounds.height) * 0.22
        placeholder.bounds = CGRect(x: 0, y: 0, width: side, height: side)
        placeholder.center = CGPoint(x: bounds.midX, y: bounds.midY)

        updateMask()
    }

    /// Installs (or removes) the shape mask. Non-rectangular cells clip to a
    /// `CAShapeLayer` path — this fits the existing GPU layer tree with no change
    /// to how pan/zoom transforms are applied.
    func setClipShape(_ shape: CellClipShape) {
        guard shape != clipShape else { return }
        clipShape = shape
        if shape.isRectangle {
            layer.mask = nil
        } else {
            layer.mask = shapeMask
        }
        setNeedsLayout()
    }

    private func updateMask() {
        guard !clipShape.isRectangle, bounds.width > 0 else { return }
        // Path is generated fresh from the current bounds — no implicit animation,
        // so the mask tracks resize/rotation crisply.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        shapeMask.frame = bounds
        shapeMask.path = clipShape.path(in: bounds)
        CATransaction.commit()
    }

    func setImage(_ image: CGImage?) {
        if let image {
            imageView.image = UIImage(cgImage: image)
            imageView.isHidden = false
            placeholder.isHidden = true
            backgroundColor = .black
        } else {
            imageView.image = nil
            imageView.isHidden = true
            placeholder.isHidden = false
            backgroundColor = .secondarySystemBackground
        }
    }

    /// Applies pan (reference pts × factor), rotation and zoom around the centre.
    func setGeometryTransform(_ transform: CellTransform, factor: CGFloat) {
        imageView.transform = CGAffineTransform(
            translationX: CGFloat(transform.panX) * factor,
            y: CGFloat(transform.panY) * factor
        )
        .rotated(by: CGFloat(transform.rotationRadians))
        .scaledBy(x: CGFloat(transform.zoom), y: CGFloat(transform.zoom))
    }
}

// MARK: - Text overlay view

/// One text zone on the canvas. A vertically-centring UILabel that renders the
/// exact attributed string `TextRendering` produces, so the live preview matches
/// the Core Graphics export. Interactive: a pan drags it around the canvas (with
/// the same alignment snapping as stickers) and a tap opens its styling sheet.
final class TextOverlayView: UIView {

    private let label = UILabel()
    private let selectionLayer = CAShapeLayer()

    /// The overlay this view currently renders — set on `configure` and mutated as
    /// the view drags itself, so its emitted geometry always carries the right id.
    private var overlay: TextOverlay?

    /// The finger's true (unsnapped) centre during a drag; snapping is layered on
    /// top of this as a display magnet so the zone never feels "stuck" to a guide.
    private var dragRawCenter: CGPoint = .zero
    private var wasSnapped = false

    var onChanged: ((TextOverlay) -> Void)?
    var onCommitted: (() -> Void)?
    var onTapped: ((UUID) -> Void)?
    /// Reports the engaged snap guides (normalized x's, y's); an empty pair clears them.
    var onGuidesChanged: (([CGFloat], [CGFloat]) -> Void)?

    private var isDragging: Bool = false {
        didSet { selectionLayer.isHidden = !isDragging }
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = true
        backgroundColor = .clear
        clipsToBounds = true
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
        label.attributedText = TextRendering.attributedString(for: overlay, fontScale: fontScale)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        label.frame = bounds
        selectionLayer.frame = bounds
        selectionLayer.path = UIBezierPath(
            roundedRect: bounds.insetBy(dx: 1, dy: 1), cornerRadius: 6
        ).cgPath
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

// MARK: - Sticker overlay view

/// One sticker on the canvas: a tinted SF Symbol (drawn via `StickerRendering`, so
/// the live view matches the export) that the user can drag, pinch, rotate, and
/// double-tap to delete. Unlike text, stickers are freely positioned, so each view
/// owns its gestures and reports normalized geometry back through closures.
final class StickerOverlayView: UIView {

    let stickerID: UUID
    private var overlay: StickerOverlay
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
        didSet { selectionLayer.isHidden = !isSelected }
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
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Positions the view from its normalized model at the given container size and
    /// re-renders the symbol crisply at the resolved point side.
    func apply(overlay: StickerOverlay, in containerSize: CGSize) {
        self.overlay = overlay
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
        imageView.image = StickerRendering.image(for: overlay, sidePx: side)
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
