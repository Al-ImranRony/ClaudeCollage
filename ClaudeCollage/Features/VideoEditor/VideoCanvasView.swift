//
//  VideoCanvasView.swift
//  ClaudeCollage
//
//  Step 04 slice 5b — the video editor's canvas.
//
//  Its backing layer IS an `AVPlayerLayer` (the plan's requirement), so the composed
//  collage plays in real time with zero extra compositing on the UI thread: the
//  player item already carries the `AVVideoComposition` (per-cell layout, transforms
//  and transition ramps) and the `AVAudioMix` (per-cell volume + music), so what you
//  see and hear here is exactly what the exporter writes.
//
//  Hosting an AVPlayerLayer inside SwiftUI needs a UIViewRepresentable bridge that
//  gets messy around player lifecycle and KVO — UIKit owns it cleanly, which is why
//  this screen is UIKit while the control sheets are SwiftUI.
//
//  Two things layer ABOVE the player:
//  • `overlayImageView` — the baked text/sticker image. AVPlayer ignores the
//    `AVVideoCompositionCoreAnimationTool`, and the exporter draws the same image at
//    write-time (slice 4), so compositing it here keeps preview == export.
//  • `cellViews` — selection chrome + "tap to add" placeholders for empty slots.
//

import AVFoundation
import UIKit

final class VideoCanvasView: UIView {

    override class var layerClass: AnyClass { AVPlayerLayer.self }

    var playerLayer: AVPlayerLayer {
        // Safe: `layerClass` above guarantees the backing layer's type.
        guard let layer = layer as? AVPlayerLayer else {
            fatalError("VideoCanvasView backing layer must be AVPlayerLayer")
        }
        return layer
    }

    var player: AVPlayer? {
        get { playerLayer.player }
        set { playerLayer.player = newValue }
    }

    /// The baked text/sticker overlay, drawn above the video (matches the export).
    private let overlayImageView = UIImageView()
    /// One chrome view per layout slot (placeholder + selection outline).
    private var cellViews: [UIView] = []

    private var canvasSize: CGSize = CGSize(width: 1, height: 1)
    private var cellFrames: [CGRect] = []

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        playerLayer.videoGravity = .resizeAspect
        clipsToBounds = true
        layer.cornerRadius = Theme.Radius.md

        overlayImageView.contentMode = .scaleToFill
        overlayImageView.isUserInteractionEnabled = false
        addSubview(overlayImageView)

        isAccessibilityElement = false
        accessibilityIdentifier = "videoCanvas"
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Configuration

    /// Lays out the slot chrome. `frames` are in canvas pixels; they're scaled into
    /// view space by `canvasToView`.
    func configure(canvasSize: CGSize, cellFrames frames: [CGRect],
                   filled: [Bool], selectedIndex: Int?) {
        self.canvasSize = canvasSize
        self.cellFrames = frames

        // Rebuild the chrome views when the slot count changes (layout switch).
        if cellViews.count != frames.count {
            cellViews.forEach { $0.removeFromSuperview() }
            cellViews = frames.map { _ in makeCellView() }
            cellViews.forEach { addSubview($0) }
        }

        for (index, cellView) in cellViews.enumerated() {
            let isFilled = filled.indices.contains(index) ? filled[index] : false
            let isSelected = (index == selectedIndex)
            // A filled cell shows the video through it — only its outline matters.
            cellView.backgroundColor = isFilled ? .clear : Theme.Color.controlFill
            cellView.layer.borderWidth = isSelected ? 3 : 1
            cellView.layer.borderColor = (isSelected ? Theme.Color.accent
                                                     : Theme.Color.separator).cgColor
            cellView.accessibilityIdentifier = "videoCell-\(index)"
            if let plus = cellView.subviews.first as? UILabel {
                plus.isHidden = isFilled
            }
        }
        setNeedsLayout()
    }

    /// The baked text/sticker layer (nil clears it).
    func setOverlayImage(_ image: UIImage?) {
        overlayImageView.image = image
        overlayImageView.isHidden = (image == nil)
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        overlayImageView.frame = bounds
        let transform = canvasToView()
        for (index, cellView) in cellViews.enumerated() where cellFrames.indices.contains(index) {
            cellView.frame = cellFrames[index].applying(transform)
        }
    }

    /// Maps canvas pixels → view points. The view is sized to the canvas aspect
    /// ratio by the VC, so this is a uniform scale.
    private func canvasToView() -> CGAffineTransform {
        guard canvasSize.width > 0, canvasSize.height > 0 else { return .identity }
        return CGAffineTransform(scaleX: bounds.width / canvasSize.width,
                                 y: bounds.height / canvasSize.height)
    }

    // MARK: - Hit testing

    /// The layout slot under a point in this view's coordinates, or nil.
    func cellIndex(at point: CGPoint) -> Int? {
        guard canvasSize.width > 0, canvasSize.height > 0, bounds.width > 0 else { return nil }
        let canvasPoint = CGPoint(x: point.x * canvasSize.width / bounds.width,
                                  y: point.y * canvasSize.height / bounds.height)
        return cellFrames.firstIndex { $0.contains(canvasPoint) }
    }

    // MARK: - Private

    private func makeCellView() -> UIView {
        let cellView = UIView()
        cellView.isUserInteractionEnabled = false   // the VC owns the tap gesture
        cellView.layer.cornerRadius = Theme.Radius.sm
        cellView.clipsToBounds = true

        let plus = UILabel()
        plus.text = "+"
        plus.font = Theme.Typography.title
        plus.textColor = Theme.Color.textSecondary
        plus.textAlignment = .center
        plus.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(plus)
        NSLayoutConstraint.activate([
            plus.centerXAnchor.constraint(equalTo: cellView.centerXAnchor),
            plus.centerYAnchor.constraint(equalTo: cellView.centerYAnchor),
        ])
        return cellView
    }
}
