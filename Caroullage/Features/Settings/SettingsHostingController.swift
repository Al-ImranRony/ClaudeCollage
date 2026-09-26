//
//  SettingsHostingController.swift
//  Caroullage
//
//  Home retention, phase 3. The thin UIKit wrapper the coordinator presents,
//  the same shape as `PaywallHostingController.sheet`.
//

import SwiftUI
import UIKit

@MainActor
final class SettingsHostingController: UIHostingController<SettingsView> {

    static func sheet(model: SettingsViewModel) -> SettingsHostingController {
        // Weak: this controller owns the root view whose callbacks capture it, so a
        // strong capture kept every sheet alive for the life of the process
        // (HostingControllerLifetimeTests).
        weak var controller: SettingsHostingController?
        let view = SettingsView(model: model, onDone: { controller?.dismiss(animated: true) })
        let hosting = SettingsHostingController(rootView: view)
        controller = hosting
        hosting.view.accessibilityIdentifier = "settingsScreen"
        hosting.view.backgroundColor = Theme.Color.background
        if let sheet = hosting.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
        return hosting
    }
}
