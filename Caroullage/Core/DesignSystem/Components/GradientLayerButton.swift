//
//  GradientLayerButton.swift
//  Caroullage
//
//  Step 05b Part C.
//
//  A button whose *backing layer* is the brand gradient, rather than a button
//  with a gradient sublayer inserted underneath it.
//
//  The difference is not cosmetic. `layer.insertSublayer(gradient, at: 0)` looks
//  like it puts the gradient behind everything, and it does — behind everything
//  that is a sublayer at the time. A UIButton's image is not: it arrives later
//  and, depending on how the button is configured, ends up under the gradient
//  and simply vanishes. That is exactly what happened to the floating "+", which
//  rendered as a plain brand-coloured disc with no glyph on it.
//
//  Making the gradient the backing layer removes the ordering question: every
//  subview a button ever creates draws above its own layer. A CAGradientLayer
//  with no colours behaves as a plain layer, so subclasses that do not want a
//  gradient pay nothing for inheriting one.
//

import UIKit

@MainActor
public class GradientLayerButton: UIButton {

    public override class var layerClass: AnyClass { CAGradientLayer.self }

    public var gradientLayer: CAGradientLayer? { layer as? CAGradientLayer }

    private var customGradient: (start: UIColor, end: UIColor)?

    /// Paints the brand gradient for the current appearance and keeps it in step
    /// with later appearance changes. CGColors are resolved, not dynamic, so
    /// nothing repaints a gradient on its own.
    public func useBrandGradient() {
        gradientLayer?.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer?.endPoint = CGPoint(x: 1, y: 1)
        refreshBrandGradient()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: Self, _) in
            button.refreshBrandGradient()
        }
    }

    /// Paints a gradient from any two theme colours, resolving them for the
    /// current appearance and re-resolving on change — CGColors are static, so
    /// without this a themed gradient keeps its light-mode colours in the dark.
    public func useGradient(from start: UIColor, to end: UIColor) {
        gradientLayer?.startPoint = CGPoint(x: 0, y: 0)
        gradientLayer?.endPoint = CGPoint(x: 1, y: 1)
        customGradient = (start, end)
        refreshCustomGradient()
        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (button: Self, _) in
            button.refreshCustomGradient()
        }
    }

    private func refreshBrandGradient() {
        gradientLayer?.colors = Theme.Color.brandGradient(for: traitCollection)
    }

    private func refreshCustomGradient() {
        guard let customGradient else { return }
        gradientLayer?.colors = [
            customGradient.start.resolvedColor(with: traitCollection).cgColor,
            customGradient.end.resolvedColor(with: traitCollection).cgColor,
        ]
    }
}
