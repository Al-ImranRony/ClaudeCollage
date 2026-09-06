//
//  EditorPanelPresenter.swift
//  Caroullage
//
//  The swap-in panel's presentation, owned by an editor screen rather than
//  reimplemented in each one. `GridEditorViewController` and
//  `VideoEditorViewController` had verbatim-identical `openPanel` / `closePanel`
//  / `animateStageResize` plus the two properties they lean on.
//
//  The reason to share them is NOT the line count — it is that those lines
//  encode a UIKit constraint-ordering trap that has to be got right in a
//  specific order, and a trap documented in two places is one that gets
//  half-fixed later. See `collapsedHeightConstraint` and `close()`.
//
//  Deliberately a collaborator, not a base class: the two screens' `toolTapped`,
//  `setupRail` and `revalidateSelection` share almost nothing — the video
//  editor's selection is model-owned and re-entrant, the collage editor's is
//  not — so a superclass would inherit ~30 lines into two 1,400-line
//  controllers and couple two screens that should stay independent.
//

import UIKit

@MainActor
public final class EditorPanelPresenter {

    private let panel: EditorPanel
    private let rail: EditorToolRail
    /// The view whose layout is animated so the stage and the panel move
    /// together. Owned by the controller that owns this presenter.
    private unowned let host: UIView

    /// The tool whose panel is currently open, or `nil`. The rail's own
    /// `activeToolID` is a rendering detail it drops silently when its tool set
    /// changes; this is the truth about what is on screen.
    public private(set) var openToolID: EditorTool.ID?

    public var isPresenting: Bool { openToolID != nil }

    /// Called after any close, including the panel's own close button — so an
    /// owner can drop state that only makes sense while a panel is up.
    public var onClose: (() -> Void)?

    /// Collapses the panel to nothing while it has no content.
    ///
    /// **Priority 750, and toggled in a specific order.** A shown panel's own
    /// intrinsic content sizing is ALSO 750, so leaving this active while
    /// content is attached ties silently — no console warning — instead of
    /// reliably picking the content's real size. `open` therefore deactivates it
    /// BEFORE `show`, and `close` reactivates it only once the outgoing content
    /// is synchronously gone.
    ///
    /// The owner activates this alongside its own layout constraints; it is
    /// created here so the whole trap lives in one file.
    public let collapsedHeightConstraint: NSLayoutConstraint

    public init(panel: EditorPanel, rail: EditorToolRail, host: UIView) {
        self.panel = panel
        self.rail = rail
        self.host = host
        collapsedHeightConstraint = panel.heightAnchor.constraint(equalToConstant: 0)
        collapsedHeightConstraint.priority = .defaultHigh
        panel.onClose = { [weak self] in self?.close() }
    }

    public func open(_ content: UIView, title: String, id: EditorTool.ID) {
        openToolID = id
        rail.setActiveTool(id)
        // Must run BEFORE `show` — see `collapsedHeightConstraint`.
        collapsedHeightConstraint.isActive = false
        panel.show(content, title: title, animated: true)
        animateResize()
    }

    /// Closes whatever is open. A no-op-safe call: closing nothing is harmless,
    /// which is what lets an owner close unconditionally before swapping context.
    public func close() {
        openToolID = nil
        rail.setActiveTool(nil)
        // Un-animated: `EditorPanel.hide(animated:)` keeps its outgoing content
        // attached (with the same 750-priority sizing) until its OWN fade
        // finishes, so reactivating the collapsed height at the same moment
        // would tie against that still-attached content instead of cleanly
        // winning. Hiding un-animated removes the content synchronously, so by
        // the time the constraint goes back up nothing contests it. The stage's
        // resize below is still animated, so the canvas growing back to fill the
        // freed space reads as one continuous motion even though the panel
        // itself disappears a beat faster.
        panel.hide(animated: false)
        collapsedHeightConstraint.isActive = true
        animateResize()
        onClose?()
    }

    /// The stage and the panel share one animation block so the canvas grows and
    /// shrinks smoothly instead of jumping a frame after the panel moves.
    public func animateResize() {
        guard !Theme.Motion.isReduced else { return host.layoutIfNeeded() }
        UIView.animate(
            withDuration: Theme.Motion.standard,
            delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity,
            options: [.allowUserInteraction]
        ) {
            self.host.layoutIfNeeded()
        }
    }
}
