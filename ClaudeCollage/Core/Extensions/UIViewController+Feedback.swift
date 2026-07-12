//
//  UIViewController+Feedback.swift
//  ClaudeCollage
//
//  Step 01 — lightweight toast + haptic helpers shared across editors.
//

import UIKit

extension UIViewController {

    /// Shows a transient capsule toast that auto-dismisses.
    func showToast(_ message: String, duration: TimeInterval = 1.8) {
        let label = PaddingLabel()
        label.text = message
        label.textColor = .white
        label.font = Theme.Typography.subheadline
        label.numberOfLines = 0
        label.textAlignment = .center
        label.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        label.layer.cornerRadius = Theme.Radius.md
        label.layer.cornerCurve = .continuous
        label.clipsToBounds = true
        label.alpha = 0
        label.translatesAutoresizingMaskIntoConstraints = false

        view.addSubview(label)
        NSLayoutConstraint.activate([
            label.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            label.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor, constant: -24),
            label.leadingAnchor.constraint(greaterThanOrEqualTo: view.leadingAnchor, constant: 32),
            label.trailingAnchor.constraint(lessThanOrEqualTo: view.trailingAnchor, constant: -32),
        ])

        UIView.animate(withDuration: 0.25, animations: { label.alpha = 1 }) { _ in
            UIView.animate(withDuration: 0.25, delay: duration, options: []) {
                label.alpha = 0
            } completion: { _ in
                label.removeFromSuperview()
            }
        }
    }

    func haptic(_ style: UIImpactFeedbackGenerator.FeedbackStyle = .light) {
        UIImpactFeedbackGenerator(style: style).impactOccurred()
    }

    func notify(_ type: UINotificationFeedbackGenerator.FeedbackType) {
        UINotificationFeedbackGenerator().notificationOccurred(type)
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
