//
//  BezierEditorViewController.swift
//  ClaudeCollage
//
//  Step 02 — the premium custom-shape editor. The user traces a closed boundary
//  by tapping to drop anchor points, dragging a point to adjust it, and
//  long-pressing to delete one. Snap guides (centre cross + thirds) help align.
//  On Done the closed path is normalized to 0…1 and returned as a
//  `CellClipShape.custom`, applied to the target cell.
//
//  v1 uses straight segments between anchors; curve smoothing can be layered on
//  later without changing the stored representation.
//

import UIKit

@MainActor
final class BezierEditorViewController: UIViewController {

    /// Called with the drawn shape (normalized to the draw area), or `nil` on cancel.
    var onFinish: ((CellClipShape?) -> Void)?

    private let drawArea = UIView()
    private let guidesLayer = CAShapeLayer()
    private let pathLayer = CAShapeLayer()
    private var points: [CGPoint] = []          // in drawArea coordinates
    private var handles: [UIView] = []
    private var draggingIndex: Int?

    private let hint = UILabel()

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = UIColor.black.withAlphaComponent(0.85)
        title = "Custom Shape"

        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .cancel, target: self, action: #selector(cancelTapped))
        let done = UIBarButtonItem(title: "Done", style: .done, target: self, action: #selector(doneTapped))
        navigationItem.rightBarButtonItems = [
            done,
            UIBarButtonItem(image: UIImage(systemName: "arrow.uturn.backward"), style: .plain,
                            target: self, action: #selector(undoPoint)),
        ]

        setupDrawArea()
        setupHint()
    }

    private func setupDrawArea() {
        drawArea.translatesAutoresizingMaskIntoConstraints = false
        drawArea.backgroundColor = UIColor(white: 0.1, alpha: 1)
        drawArea.layer.cornerRadius = Theme.Radius.md
        drawArea.layer.cornerCurve = .continuous
        drawArea.clipsToBounds = true
        view.addSubview(drawArea)

        NSLayoutConstraint.activate([
            drawArea.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            drawArea.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            drawArea.widthAnchor.constraint(equalTo: view.widthAnchor, multiplier: 0.86),
            drawArea.heightAnchor.constraint(equalTo: drawArea.widthAnchor),
        ])

        guidesLayer.strokeColor = UIColor(white: 1, alpha: 0.14).cgColor
        guidesLayer.lineWidth = 1
        drawArea.layer.addSublayer(guidesLayer)

        pathLayer.fillColor = Theme.Color.accent.withAlphaComponent(0.28).cgColor
        pathLayer.strokeColor = Theme.Color.accent.cgColor
        pathLayer.lineWidth = 2
        pathLayer.lineJoin = .round
        drawArea.layer.addSublayer(pathLayer)

        drawArea.addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tapped)))
        let pan = UIPanGestureRecognizer(target: self, action: #selector(panned))
        drawArea.addGestureRecognizer(pan)
        let hold = UILongPressGestureRecognizer(target: self, action: #selector(longPressed))
        hold.minimumPressDuration = 0.4
        drawArea.addGestureRecognizer(hold)
    }

    private func setupHint() {
        hint.text = "Tap to add points · drag to adjust · hold to delete"
        hint.font = Theme.Typography.caption
        hint.textColor = UIColor(white: 1, alpha: 0.6)
        hint.textAlignment = .center
        hint.numberOfLines = 0
        hint.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(hint)
        NSLayoutConstraint.activate([
            hint.topAnchor.constraint(equalTo: drawArea.bottomAnchor, constant: 16),
            hint.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 24),
            hint.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -24),
        ])
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        drawGuides()
        redraw()
    }

    // MARK: - Gestures

    @objc private func tapped(_ g: UITapGestureRecognizer) {
        let point = snapped(g.location(in: drawArea))
        points.append(point)
        addHandle(at: point)
        Haptics.tap()
        redraw()
    }

    @objc private func panned(_ g: UIPanGestureRecognizer) {
        let location = g.location(in: drawArea)
        switch g.state {
        case .began:
            draggingIndex = nearestPointIndex(to: location, within: 44)
        case .changed:
            guard let index = draggingIndex, points.indices.contains(index) else { return }
            points[index] = snapped(location)
            handles[index].center = points[index]
            redraw()
        default:
            draggingIndex = nil
        }
    }

    @objc private func longPressed(_ g: UILongPressGestureRecognizer) {
        guard g.state == .began else { return }
        guard let index = nearestPointIndex(to: g.location(in: drawArea), within: 44) else { return }
        points.remove(at: index)
        handles.remove(at: index).removeFromSuperview()
        Haptics.impact()
        redraw()
    }

    @objc private func undoPoint() {
        guard !points.isEmpty else { return }
        points.removeLast()
        handles.removeLast().removeFromSuperview()
        redraw()
    }

    // MARK: - Actions

    @objc private func cancelTapped() {
        onFinish?(nil)
        dismiss(animated: true)
    }

    @objc private func doneTapped() {
        guard points.count >= 3 else {
            Haptics.warning()
            let alert = UIAlertController(
                title: "Add More Points",
                message: "A custom shape needs at least three points.",
                preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        let normalized = points.map {
            CGPoint(x: $0.x / drawArea.bounds.width, y: $0.y / drawArea.bounds.height)
        }
        Haptics.success()
        onFinish?(.custom(points: normalized))
        dismiss(animated: true)
    }

    // MARK: - Drawing

    private func redraw() {
        let path = UIBezierPath()
        if let first = points.first {
            path.move(to: first)
            for point in points.dropFirst() { path.addLine(to: point) }
            if points.count >= 3 { path.close() }
        }
        pathLayer.path = path.cgPath
    }

    private func drawGuides() {
        let bounds = drawArea.bounds
        let path = UIBezierPath()
        // Centre cross.
        path.move(to: CGPoint(x: bounds.midX, y: 0)); path.addLine(to: CGPoint(x: bounds.midX, y: bounds.height))
        path.move(to: CGPoint(x: 0, y: bounds.midY)); path.addLine(to: CGPoint(x: bounds.width, y: bounds.midY))
        // Thirds.
        for f in [1.0 / 3, 2.0 / 3] {
            path.move(to: CGPoint(x: bounds.width * f, y: 0)); path.addLine(to: CGPoint(x: bounds.width * f, y: bounds.height))
            path.move(to: CGPoint(x: 0, y: bounds.height * f)); path.addLine(to: CGPoint(x: bounds.width, y: bounds.height * f))
        }
        guidesLayer.frame = bounds
        guidesLayer.path = path.cgPath
    }

    // MARK: - Helpers

    private func addHandle(at point: CGPoint) {
        let handle = UIView(frame: CGRect(x: 0, y: 0, width: 18, height: 18))
        handle.center = point
        handle.backgroundColor = Theme.Color.accent
        handle.layer.cornerRadius = 9
        handle.layer.borderWidth = 2
        handle.layer.borderColor = UIColor.white.cgColor
        handle.isUserInteractionEnabled = false
        drawArea.addSubview(handle)
        handles.append(handle)
    }

    private func nearestPointIndex(to location: CGPoint, within radius: CGFloat) -> Int? {
        var best: (index: Int, distance: CGFloat)?
        for (index, point) in points.enumerated() {
            let d = hypot(point.x - location.x, point.y - location.y)
            if d <= radius, best == nil || d < best!.distance { best = (index, d) }
        }
        return best?.index
    }

    /// Snaps to centre / third lines when close, for tidy shapes.
    private func snapped(_ point: CGPoint) -> CGPoint {
        let bounds = drawArea.bounds
        let threshold: CGFloat = 12
        let xs = [0, 1.0 / 3, 0.5, 2.0 / 3, 1].map { $0 * bounds.width }
        let ys = [0, 1.0 / 3, 0.5, 2.0 / 3, 1].map { $0 * bounds.height }
        var p = point
        if let sx = xs.first(where: { abs($0 - point.x) < threshold }) { p.x = sx }
        if let sy = ys.first(where: { abs($0 - point.y) < threshold }) { p.y = sy }
        return p
    }
}
