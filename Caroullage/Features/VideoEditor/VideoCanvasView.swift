//
//  VideoCanvasView.swift
//  Caroullage
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
//  • `textViews` / `stickerViews` — the same pooled, interactive overlay views the
//    photo collage editor uses (`TextOverlayView` / `StickerOverlayView`), which
//    already draw through the shared `TextRendering`/`StickerRendering` helpers, so
//    a caption or sticker looks identical whether the project is a photo or video
//    collage. There is deliberately no second, baked-image copy of this layer: an
//    earlier slice tried compositing `bundle.overlayImage` into its own image view
//    here too, but that view sat hidden underneath these live ones (and, once a
//    text overlay carries timing, `overlayImage` is nil) — see `setPreviewTime`
//    below for how the live views themselves follow playback time instead.
//    `bundle.overlayImage` / `timedOverlays` still exist for the EXPORT, which
//    draws into a `CVPixelBuffer` where UIKit views can't run.
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

    /// One chrome view per layout slot (placeholder + selection outline).
    private var cellViews: [UIView] = []

    private var canvasSize: CGSize = CGSize(width: 1, height: 1)
    private var cellFrames: [CGRect] = []

    // Interactive text/sticker overlay views (reused from the grid editor), layered
    // above the player — the only overlay rendering path in the preview; see the
    // header comment for why there's no separate baked-image layer.
    private var textViews: [TextOverlayView] = []
    private var stickerViews: [StickerOverlayView] = []
    private var textModels: [TextOverlay] = []
    private var stickerModels: [StickerOverlay] = []

    /// The composition time the preview is showing, in seconds — pushed by the VC's
    /// player time observer. Drives which timed text overlays are on screen so the
    /// canvas matches what the export will write for that same instant. Same
    /// half-open `[start, end)` contract as `TextOverlay.isVisible(at:)`, compared
    /// with no tolerance: the caller must feed the same `CMTime.seconds` conversion
    /// the export uses, or an in/out point landing exactly on a frame boundary could
    /// disagree between the two.
    private var previewTime: Double = 0

    var onTextChanged: ((TextOverlay) -> Void)?
    var onTextCommitted: (() -> Void)?
    var onTextTapped: ((UUID) -> Void)?
    var onStickerChanged: ((StickerOverlay) -> Void)?
    var onStickerCommitted: (() -> Void)?
    var onStickerDeleted: ((UUID) -> Void)?
    var onStickerSelected: ((UUID) -> Void)?

    // MARK: - Init

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = Theme.Color.surface
        playerLayer.videoGravity = .resizeAspect
        clipsToBounds = true
        layer.cornerRadius = Theme.Radius.md

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
            if let chip = cellView.subviews.first as? EmptyZoneChipView {
                chip.isHidden = isFilled
            }
        }
        setNeedsLayout()
    }

    // MARK: - Interactive overlays

    /// Pools/rebuilds the interactive text views and repositions them. Wires each
    /// view's gesture callbacks back out through this canvas.
    ///
    /// `selected` mirrors `updateStickerOverlays(_:selected:)` — Task 6's "Text
    /// selected" contextual rail group is not the only feedback that something
    /// is selected: `TextOverlayView` already carries the same persistent
    /// selection chrome `StickerOverlayView` does, so the tapped zone shows it
    /// on the canvas too.
    func updateTextOverlays(_ overlays: [TextOverlay], selected: UUID? = nil) {
        textModels = overlays
        if textViews.count != overlays.count {
            textViews.forEach { $0.removeFromSuperview() }
            textViews = overlays.map { _ in
                let view = TextOverlayView()
                view.onChanged = { [weak self] in self?.onTextChanged?($0) }
                view.onCommitted = { [weak self] in self?.onTextCommitted?() }
                view.onTapped = { [weak self] in self?.onTextTapped?($0) }
                addSubview(view)
                return view
            }
        }
        for (view, overlay) in zip(textViews, overlays) {
            view.isSelected = overlay.id == selected
        }
        textViews.forEach { bringSubviewToFront($0) }
        stickerViews.forEach { bringSubviewToFront($0) }   // stickers above text
        setNeedsLayout()
        // A freshly pooled view defaults to visible — refresh immediately so a
        // timed-out caption doesn't flash on screen before the next player tick.
        refreshTextVisibility()
    }

    func updateStickerOverlays(_ overlays: [StickerOverlay], selected: UUID?) {
        stickerModels = overlays
        stickerViews.forEach { $0.removeFromSuperview() }
        stickerViews = overlays.map { overlay in
            let view = StickerOverlayView(overlay: overlay)
            view.onChanged = { [weak self] in self?.onStickerChanged?($0) }
            view.onCommitted = { [weak self] in self?.onStickerCommitted?() }
            view.onDeleted = { [weak self] in self?.onStickerDeleted?($0) }
            view.onSelected = { [weak self] in self?.onStickerSelected?($0) }
            view.isSelected = overlay.id == selected
            addSubview(view)
            return view
        }
        setNeedsLayout()
    }

    /// True when an interactive text/sticker view sits under the point — the VC uses
    /// this to skip cell-tap handling (the overlay's own gestures take the touch).
    func hasInteractiveOverlay(at point: CGPoint) -> Bool {
        stickerViews.contains { $0.frame.contains(point) }
            || textViews.contains { $0.frame.contains(point) }
    }

    // MARK: - Playback time

    /// The VC's player time observer calls this ~10x/sec with the current playback
    /// time (seconds). Hides/shows the pooled text views so a caption is only ever
    /// on screen inside its `startTime`/`endTime` window — the same thing the
    /// export's per-frame overlay selection does, so preview and export agree.
    func setPreviewTime(_ seconds: Double) {
        guard seconds != previewTime else { return }
        previewTime = seconds
        refreshTextVisibility()
    }

    /// Test seam: the pooled text overlay views, to assert visibility directly
    /// rather than through screenshot comparison.
    var textOverlayViewsForTesting: [UIView] { textViews }

    private func refreshTextVisibility() {
        for (view, overlay) in zip(textViews, textModels) {
            view.isHidden = !overlay.isVisible(at: previewTime)
        }
    }

    // MARK: - Layout

    override func layoutSubviews() {
        super.layoutSubviews()
        let transform = canvasToView()
        for (index, cellView) in cellViews.enumerated() where cellFrames.indices.contains(index) {
            cellView.frame = cellFrames[index].applying(transform)
            (cellView.subviews.first as? EmptyZoneChipView)?.canvasShortSide =
                min(bounds.width, bounds.height)
        }
        layoutOverlays()
    }

    /// Positions the interactive overlay views from their normalized models (bounds
    /// == the canvas, so 1:1 with the composited video the player shows). Font scale
    /// maps reference-canvas point sizes onto the on-screen size, matching export.
    private func layoutOverlays() {
        let fontScale = canvasSize.width > 0 ? bounds.width / canvasSize.width : 1
        for (index, overlay) in textModels.enumerated() where textViews.indices.contains(index) {
            textViews[index].frame = TextRendering.frame(for: overlay, in: bounds.size)
            textViews[index].configure(with: overlay, fontScale: fontScale)
        }
        for (index, overlay) in stickerModels.enumerated() where stickerViews.indices.contains(index) {
            stickerViews[index].apply(overlay: overlay, in: bounds.size)
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
        // Cells render with sharp rectangular edges — no per-cell corner-radius
        // concept exists in the video composition — so the selection chrome must
        // stay square too, or its rounded outline reads as misaligned against the
        // rectangular video underneath it.
        cellView.clipsToBounds = true

        // The same "+" chip the photo canvas shows in an empty zone, so a slot
        // that wants media looks the same in both editors.
        let chip = EmptyZoneChipView()
        chip.translatesAutoresizingMaskIntoConstraints = false
        cellView.addSubview(chip)
        NSLayoutConstraint.activate([
            chip.leadingAnchor.constraint(equalTo: cellView.leadingAnchor),
            chip.trailingAnchor.constraint(equalTo: cellView.trailingAnchor),
            chip.topAnchor.constraint(equalTo: cellView.topAnchor),
            chip.bottomAnchor.constraint(equalTo: cellView.bottomAnchor),
        ])
        return cellView
    }
}
