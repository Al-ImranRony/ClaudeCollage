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
        var controller: SettingsHostingController!
        let view = SettingsView(model: model, onDone: { controller?.dismiss(animated: true) })
        controller = SettingsHostingController(rootView: view)
        controller.view.accessibilityIdentifier = "settingsScreen"
        controller.view.backgroundColor = Theme.Color.background
        if let sheet = controller.sheetPresentationController {
            sheet.detents = [.large()]
            sheet.prefersGrabberVisible = true
            sheet.preferredCornerRadius = Theme.Radius.xl
        }
        return controller
    }
}
