//
//  TopFadeView.swift
//  Caroullage
//
//  Step 06 UI pass — the fade under a transparent navigation bar.
//
//  With content scrolling under the bar, something has to keep the title legible
//  and stop rows from colliding with the status bar. An opaque bar would do it,
//  but it draws a hard edge across the screen and undoes the depth the floating
//  tab bar just bought. So the bar is transparent and this sits behind it: solid
//  at the very top, fading out by the time it reaches the bar's bottom, so
//  content dissolves toward the top edge instead of being cut off by a line.
//

import UIKit

@MainActor
final class TopFadeView: UIView {

    override class var layerClass: AnyClass { CAGradientLayer.self }

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        guard let gradient = layer as? CAGradientLayer else { return }
        gradient.startPoint = CGPoint(x: 0.5, y: 0)
        gradient.endPoint = CGPoint(x: 0.5, y: 1)
        // Solid for the status bar's depth, still mostly opaque behind the title,
        // then gone. The middle stop is what stops it looking like a grey band.
        gradient.locations = [0, 0.55, 1]
        refreshColours()

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.refreshColours()
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func refreshColours() {
        let background = Theme.Color.background
        (layer as? CAGradientLayer)?.colors = [
            background.cgColor,
            background.withAlphaComponent(0.92).cgColor,
            background.withAlphaComponent(0).cgColor,
        ]
    }

    /// Adds the fade to `parent`, above `content` so it covers what scrolls, and
    /// below anything pinned to the top. Sized to the nav bar plus a little more,
    /// which is where the gradient has finished anyway.
    @discardableResult
    static func install(in parent: UIViewController, above content: UIView) -> TopFadeView {
        let fade = TopFadeView()
        fade.translatesAutoresizingMaskIntoConstraints = false
        parent.view.insertSubview(fade, aboveSubview: content)

        NSLayoutConstraint.activate([
            fade.topAnchor.constraint(equalTo: parent.view.topAnchor),
            fade.leadingAnchor.constraint(equalTo: parent.view.leadingAnchor),
            fade.trailingAnchor.constraint(equalTo: parent.view.trailingAnchor),
            // Follows the safe area, so it shrinks with the large title as it
            // collapses instead of hanging over the content below.
            fade.bottomAnchor.constraint(
                equalTo: parent.view.safeAreaLayoutGuide.topAnchor, constant: 24),
        ])
        return fade
    }
}
