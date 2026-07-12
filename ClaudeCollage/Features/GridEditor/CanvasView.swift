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
}

final class CanvasView: UIView {

    /// The aspect-fit square the collage is drawn inside. Its background colour
    /// shows through the gaps between cells.
    private let contentContainer = UIView()
    private var cellViews: [CellContentView] = []
    private var model: CanvasModel?

    /// On-screen points per reference point (contentContainer.width / canvasSize.width).
    private(set) var referenceScaleFactor: CGFloat = 1

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .clear
        contentContainer.clipsToBounds = false
        addSubview(contentContainer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Configuration

    /// Rebuilds / repositions cell views for a discrete change (layout, border,
    /// background, photo add/clear, undo). NOT called during gestures.
    func configure(with model: CanvasModel) {
        let countChanged = model.cells.count != cellViews.count
        self.model = model

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
        layoutCanvas()
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
    }

    // MARK: - Hit testing

    /// The on-screen rect occupied by the collage (this view's coordinates).
    var displayedContentRect: CGRect { contentContainer.frame }

    /// Which cell contains `point` (this view's coordinates), if any.
    func cellIndex(at point: CGPoint) -> Int? {
        let local = convert(point, to: contentContainer)
        return cellViews.firstIndex { $0.frame.contains(local) }
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
