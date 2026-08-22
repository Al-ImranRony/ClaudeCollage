//
//  UIViewController+Feedback.swift
//  ClaudeCollage
//
//  Step 01 — lightweight toast + haptic helpers shared across editors.
//  Step 05b — themed, Reduce-Motion aware, and routed through `Haptics`.
//

import UIKit

extension UIViewController {

    /// Shows a transient capsule toast that auto-dismisses.
    ///
    /// For routine confirmations ("Sticker removed"). An export finishing is not
    /// routine — use `showSuccess` for that.
    func showToast(_ message: String, duration: TimeInterval = 1.8) {
        let label = PaddingLabel()
        label.text = message
        label.textColor = Theme.Color.textOnToast
        label.font = Theme.Typography.subheadline
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = Theme.Color.toast
        label.layer.cornerRadius = Theme.Radius.md
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false
        // A toast is an announcement, not a control; VoiceOver users get it as
        // one rather than having to find it.
        label.isAccessibilityElement = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(
                equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -Theme.Spacing.xl),
            label.leadingAnchor.constraint(
                greaterThanOrEqualTo: view.leadingAnchor, constant: Theme.Spacing.xxl),
            label.trailingAnchor.constraint(
                lessThanOrEqualTo: view.trailingAnchor, constant: -Theme.Spacing.xxl),
        ])

        let fade = Theme.Motion.duration(Theme.Motion.standard)
        UIView.animate(withDuration: fade, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: fade, delay: duration, options: []) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
        UIAccessibility.post(notification: .announcement, argument: message)
    }

    /// The celebration for a finished export: a gradient check that springs in,
    /// holds, and leaves. Carries its own success haptic, so callers do not fire
    /// one as well.
    func showSuccess(_ message: String) {
        Haptics.success()
        SuccessOverlayView(message: message).present(in: view)
    }
}

/// A UILabel with internal padding, used by `showToast`.
private final class PaddingLabel: UILabel {
    private let insets = UIEdgeInsets(top: 10, left: 16, bottom: 10, right: 16)

    override func drawText(in rect: CGRect) {
        super.drawText(in: rect.inset(by: insets))
    }

    override var intrinsicContentSize: CGSize {
        let size = super.intrinsicContentSize
        return CGSize(width: size.width + insets.left + insets.right,
                      height: size.height + insets.top + insets.bottom)
    }
}
