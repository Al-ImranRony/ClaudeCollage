//
//  FavouriteContextMenu.swift
//  Caroullage
//
//  Home retention, phase 4 — "Save" on a long press, everywhere a template
//  card appears.
//
//  A heart INSIDE a card was the obvious design and the wrong one: every
//  template cell is a single accessibility element with the `.button` trait,
//  so a control inside it is invisible to VoiceOver and fights the cell's own
//  tap. The menu is what iOS offers for a second action on a card, and the
//  cell gains a custom accessibility action for the same thing.
//
//  Two traps, both learned on the carousel navigator and kept here so every
//  caller inherits the fix: the action must not mutate the data source while
//  UIKit is still animating the menu away (it abandons the teardown and
//  strands the menu's container), so it is stashed and run from
//  `willEndContextMenuInteraction`; and a rounded card lifted onto the
//  default platter shows a square behind its corners, so the preview carries
//  the card's own path.
//

import UIKit

/// Holds the menu action until UIKit has finished dismissing the menu.
@MainActor
final class ContextMenuActionStash {
    private var pending: (() -> Void)?

    init() {}

    func perform(_ action: @escaping () -> Void) {
        pending = action
    }

    /// From `collectionView(_:willEndContextMenuInteraction:animator:)`.
    func complete(with animator: UIContextMenuInteractionAnimating?) {
        guard let action = pending else { return }
        pending = nil
        guard let animator else { return action() }
        animator.addCompletion(action)
    }
}

@MainActor
enum FavouriteContextMenu {

    /// The menu title for an item, in its current state.
    static func actionTitle(saved: Bool) -> String {
        saved ? String(localized: "Remove from Saved") : String(localized: "Save")
    }

    static func configuration(
        for item: FavoritesStore.Item,
        at indexPath: IndexPath,
        store: FavoritesStore = .shared,
        stash: ContextMenuActionStash,
        afterToggle: @escaping () -> Void
    ) -> UIContextMenuConfiguration {
        let saved = store.isSaved(item)
        // The index path rides on the configuration so the preview callbacks
        // find the same cell without guessing which one is highlighted.
        return UIContextMenuConfiguration(identifier: indexPath as NSIndexPath, previewProvider: nil) { _ in
            let toggle = UIAction(
                title: actionTitle(saved: saved),
                image: UIImage(systemName: saved ? "heart.slash" : "heart")
            ) { _ in
                stash.perform {
                    Haptics.tap()
                    store.toggle(item)
                    afterToggle()
                }
            }
            return UIMenu(children: [toggle])
        }
    }

    /// The lifted card with its own rounded shape, for both the highlight and
    /// the dismissal previews.
    static func preview(
        for configuration: UIContextMenuConfiguration,
        in collectionView: UICollectionView,
        cornerRadius: CGFloat = Theme.Radius.lg
    ) -> UITargetedPreview? {
        guard let indexPath = configuration.identifier as? NSIndexPath,
              let cell = collectionView.cellForItem(
                at: IndexPath(item: indexPath.item, section: indexPath.section))
        else { return nil }
        let parameters = UIPreviewParameters()
        parameters.backgroundColor = .clear
        parameters.visiblePath = UIBezierPath(roundedRect: cell.bounds, cornerRadius: cornerRadius)
        return UITargetedPreview(view: cell, parameters: parameters)
    }

    /// The VoiceOver equivalent of the long press.
    static func customAction(
        for item: FavoritesStore.Item,
        store: FavoritesStore = .shared,
        afterToggle: @escaping () -> Void
    ) -> UIAccessibilityCustomAction {
        UIAccessibilityCustomAction(name: actionTitle(saved: store.isSaved(item))) { _ in
            store.toggle(item)
            afterToggle()
            return true
        }
    }
}
