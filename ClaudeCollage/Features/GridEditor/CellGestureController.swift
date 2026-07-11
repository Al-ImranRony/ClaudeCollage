//
//  CellGestureController.swift
//  ClaudeCollage
//
//  Step 01 — composes pan + pinch + rotate on the canvas so all three drive a
//  single cell's transform simultaneously (no gesture stealing). This is the
//  reason the editor is UIKit: UIGestureRecognizer's simultaneous-recognition
//  model handles composed multi-touch precisely.
//

import UIKit

@MainActor
protocol CellGestureControllerDelegate: AnyObject {
    /// Which cell (if any) is under `point` in the canvas view's coordinates.
    func cellIndex(at point: CGPoint) -> Int?
    /// The cell's current transform (reference-canvas points).
    func currentTransform(forCellAt index: Int) -> CellTransform
    /// Points-per-reference-point on screen, to convert pan deltas.
    var referenceScaleFactor: CGFloat { get }
    /// Live transform update mid-gesture (no undo snapshot yet).
    func gestureDidUpdate(transform: CellTransform, forCellAt index: Int)
    /// All active recognizers finished — record one undo snapshot.
    func gestureDidComplete()
}

@MainActor
final class CellGestureController: NSObject {

    weak var delegate: CellGestureControllerDelegate?
    private weak var canvas: UIView?

    private var activeCell: Int?
    private var activeRecognizerCount = 0

    init(canvas: UIView) {
        self.canvas = canvas
        super.init()
        install()
    }

    private func install() {
        guard let canvas else { return }
        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan))
        pan.minimumNumberOfTouches = 1
        pan.maximumNumberOfTouches = 2
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch))
        let rotate = UIRotationGestureRecognizer(target: self, action: #selector(handleRotate))
        for recognizer in [pan, pinch, rotate] as [UIGestureRecognizer] {
            recognizer.delegate = self
            canvas.addGestureRecognizer(recognizer)
        }
    }

    // MARK: - Gesture handlers

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard let canvas else { return }
        switch gesture.state {
        case .began:
            beginIfNeeded(at: gesture.location(in: canvas))
        case .changed:
            guard let index = activeCell else { return }
            let factor = max(delegate?.referenceScaleFactor ?? 1, 0.0001)
            let translation = gesture.translation(in: canvas)
            gesture.setTranslation(.zero, in: canvas)
            var transform = delegate?.currentTransform(forCellAt: index) ?? CellTransform()
            transform.panX += Double(translation.x / factor)
            transform.panY += Double(translation.y / factor)
            delegate?.gestureDidUpdate(transform: transform, forCellAt: index)
        case .ended, .cancelled, .failed:
            endRecognizer()
        default:
            break
        }
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard let canvas else { return }
        switch gesture.state {
        case .began:
            beginIfNeeded(at: gesture.location(in: canvas))
        case .changed:
            guard let index = activeCell else { return }
            var transform = delegate?.currentTransform(forCellAt: index) ?? CellTransform()
            transform.zoom = max(0.1, min(8, transform.zoom * Double(gesture.scale)))
            gesture.scale = 1
            delegate?.gestureDidUpdate(transform: transform, forCellAt: index)
        case .ended, .cancelled, .failed:
            endRecognizer()
        default:
            break
        }
    }

    @objc private func handleRotate(_ gesture: UIRotationGestureRecognizer) {
        guard let canvas else { return }
        switch gesture.state {
        case .began:
            beginIfNeeded(at: gesture.location(in: canvas))
        case .changed:
            guard let index = activeCell else { return }
            var transform = delegate?.currentTransform(forCellAt: index) ?? CellTransform()
            transform.rotationRadians += Double(gesture.rotation)
            gesture.rotation = 0
            delegate?.gestureDidUpdate(transform: transform, forCellAt: index)
        case .ended, .cancelled, .failed:
            endRecognizer()
        default:
            break
        }
    }

    // MARK: - Active-cell bookkeeping

    private func beginIfNeeded(at point: CGPoint) {
        activeRecognizerCount += 1
        if activeCell == nil {
            activeCell = delegate?.cellIndex(at: point)
        }
    }

    private func endRecognizer() {
        activeRecognizerCount = max(0, activeRecognizerCount - 1)
        guard activeRecognizerCount == 0 else { return }
        if activeCell != nil {
            delegate?.gestureDidComplete()
        }
        activeCell = nil
    }
}

// MARK: - UIGestureRecognizerDelegate

extension CellGestureController: UIGestureRecognizerDelegate {
    // Pan + pinch + rotate must all recognize together on the same cell.
    func gestureRecognizer(
        _ gestureRecognizer: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer
    ) -> Bool {
        true
    }
}
