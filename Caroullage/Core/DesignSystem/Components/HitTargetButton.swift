//
//  HitTargetButton.swift
//  Caroullage
//
//  Step 06 phase 6.5. A button that draws small and hits large.
//
//  The panel's close chip is a 28pt circle and the timeline's chevron a 32pt
//  glyph — the right size to look at, and under Apple's 44pt minimum to touch.
//  Rather than inflate every such glyph, the control keeps its drawn bounds and
//  grows its *hit region* symmetrically to at least 44×44. Two overrides carry
//  it: `point(inside:)` so touches land, and `accessibilityFrame` so what the
//  system reports (and what Xcode's hit-region audit measures) is the region
//  you can actually hit, not the pixels you can see.
//
//  The grown region still has to be inside the superview for a touch to
//  arrive — a superview's own `point(inside:)` runs first. Give a small button
//  at least 8pt of superview on every side (a 28pt chip → 44pt).
//

import UIKit

extension UIView {
    /// `bounds` grown outward, symmetrically, to at least
    /// `Theme.Layout.minimumHitTarget` on each axis. Unchanged when already
    /// large enough.
    var minimumHitTargetBounds: CGRect {
        let dx = max(0, (Theme.Layout.minimumHitTarget - bounds.width) / 2)
        let dy = max(0, (Theme.Layout.minimumHitTarget - bounds.height) / 2)
        return bounds.insetBy(dx: -dx, dy: -dy)
    }

    /// The grown region in screen coordinates, for `accessibilityFrame`.
    fileprivate var minimumHitTargetAccessibilityFrame: CGRect {
        UIAccessibility.convertToScreenCoordinates(minimumHitTargetBounds, in: self)
    }
}

/// A `UIButton` whose hit region and accessibility frame are at least 44×44pt.
open class HitTargetButton: UIButton {
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        minimumHitTargetBounds.contains(point)
    }

    open override var accessibilityFrame: CGRect {
        get { minimumHitTargetAccessibilityFrame }
        set { super.accessibilityFrame = newValue }
    }
}

/// The same for a bare `UIControl` (the timeline's header controls).
open class HitTargetControl: UIControl {
    open override func point(inside point: CGPoint, with event: UIEvent?) -> Bool {
        minimumHitTargetBounds.contains(point)
    }

    open override var accessibilityFrame: CGRect {
        get { minimumHitTargetAccessibilityFrame }
        set { super.accessibilityFrame = newValue }
    }
}
