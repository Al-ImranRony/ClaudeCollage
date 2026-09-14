//
//  EditorControlScrollView.swift
//  Caroullage
//
//  A horizontal strip of controls that must both press and scroll — the tool
//  rail, the text-style preset strip.
//
//  A stock `UIScrollView` gets two things wrong for a strip of custom
//  `UIControl`s. It withholds touches from its content for ~150ms to decide
//  whether a scroll is starting, so a quick tap delivers press and release in
//  the same run-loop turn and the press spring never draws a frame. And once a
//  control HAS taken the touch, `touchesShouldCancel(in:)` answers `false` for
//  any `UIControl`, so a drag that starts on a held card is handed to the card
//  instead of scrolling the strip — which on a phone is the only way to reach a
//  card clipped off the trailing edge.
//
//  Delivering touches immediately and cancelling them for controls is the pair
//  `UITableView` relies on for buttons in cells: a scroll that begins on a
//  control shows its press for a frame and springs back as the strip moves.
//

import UIKit

@MainActor
public final class EditorControlScrollView: UIScrollView {

    public override init(frame: CGRect) {
        super.init(frame: frame)
        delaysContentTouches = false
        canCancelContentTouches = true
        showsHorizontalScrollIndicator = false
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    public override func touchesShouldCancel(in view: UIView) -> Bool {
        view is UIControl ? true : super.touchesShouldCancel(in: view)
    }
}
