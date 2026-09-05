//
//  EditorStage.swift
//  Caroullage
//
//  Hosts an editor's canvas and owns its geometry. The canvas takes the DOCUMENT's
//  aspect ratio through a stored, replaceable multiplier constraint — the grid
//  editor previously pinned it square, which letterboxed every 9:16 story collage
//  into 44% dead space.
//
//  The stage fills whatever space is left between the navigation bar and the panel
//  or rail beneath it, so opening a panel shrinks the canvas smoothly instead of
//  the canvas being a fixed size with a scrolling form under it.
//

import UIKit

@MainActor
public final class EditorStage: UIView {

    /// Minimum breathing room around the canvas.
    public var contentInsets = UIEdgeInsets(top: 8, left: 16, bottom: 8, right: 16) {
        didSet { setNeedsLayout() }
    }

    private var content: UIView?
    private var canvasSize = CGSize(width: 1, height: 1)

    public override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.background
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    /// Installs the canvas view, replacing any previous one.
    public func setContent(_ view: UIView) {
        content?.removeFromSuperview()
        content = view
        // Frame-driven: `layoutSubviews` positions the single child from
        // `EditorStageGeometry`, so it must NOT be under Auto Layout as well.
        view.translatesAutoresizingMaskIntoConstraints = true
        addSubview(view)
        setNeedsLayout()
    }

    /// Sets the document's aspect ratio. A degenerate size is normalised to 1:1 by
    /// `EditorStageGeometry`, so a malformed document cannot produce a zero canvas.
    public func setCanvasAspect(_ canvasSize: CGSize) {
        self.canvasSize = canvasSize
        setNeedsLayout()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        guard let content else { return }

        // Frame maths must run with an identity transform — setting `.frame` under a
        // non-identity transform is undefined. The canvas applies its pinch zoom to
        // its own inner container, so this is normally already identity; saving and
        // restoring costs nothing and makes the invariant explicit. This mirrors
        // `CanvasView.layoutCellGeometry()`.
        let transform = content.transform
        content.transform = .identity
        content.frame = EditorStageGeometry.canvasRect(
            canvasSize: canvasSize, in: bounds, insets: contentInsets)
        content.transform = transform
    }
}
