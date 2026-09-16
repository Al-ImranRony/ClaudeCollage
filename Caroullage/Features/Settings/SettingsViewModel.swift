//
//  SettingsViewModel.swift
//  Caroullage
//
//  Home retention, phase 3 — the app's first Settings screen, as state.
//
//  There was none. Restore lived only on the paywall, the legal links only
//  in its footer, and nothing could hold a notification toggle — which the
//  reminders need, because a reminder the user did not ask for is the fastest
//  way to be muted. Small on purpose: the toggle, restore, the App Store's
//  subscription page, the two legal links and the version.
//

import Foundation
import UIKit

@MainActor
public final class SettingsViewModel: ObservableObject {

    @Published public private(set) var remindersEnabled: Bool
    /// The user turned reminders on here, but iOS will not deliver them —
    /// the switch in the Settings app is off. The row then offers that app.
    @Published public private(set) var remindersBlockedBySystem = false
    @Published public private(set) var restoreMessage: String?
    @Published public private(set) var restoreFailure: String?
    @Published public private(set) var isRestoring = false
    @Published public private(set) var isPremium: Bool

    public let version: String

    private let service: PurchaseService
    private let entitlements: EntitlementStore
    private let reminders: EngagementReminderScheduler
    private let openURL: (URL) -> Void

    public init(
        service: PurchaseService = .shared,
        entitlements: EntitlementStore = .shared,
        reminders: EngagementReminderScheduler,
        bundle: Bundle = .main,
        openURL: @escaping (URL) -> Void = { UIApplication.shared.open($0) }
    ) {
        self.service = service
        self.entitlements = entitlements
        self.reminders = reminders
        self.openURL = openURL
        self.remindersEnabled = reminders.isEnabled
        // The entitlement store, not the purchase service's tier: it is the
        // gate every feature reads, and the one the debug override drives.
        self.isPremium = entitlements.isPremiumUnlocked
        let short = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let build = bundle.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
        self.version = "\(short) (\(build))"
    }

    /// Re-reads what can have changed while the sheet was away: the system
    /// switch, and the entitlement.
    public func load() async {
        isPremium = entitlements.isPremiumUnlocked
        remindersEnabled = reminders.isEnabled
        let authorization = await reminders.authorization()
        remindersBlockedBySystem = remindersEnabled && authorization == .denied
    }

    public func setReminders(_ enabled: Bool) async {
        let granted = await reminders.setEnabled(enabled)
        remindersEnabled = enabled && granted
        remindersBlockedBySystem = enabled && !granted
    }

    /// The same words the paywall uses, so a restore reads the same wherever
    /// it is started from.
    public func restore() async {
        restoreMessage = nil
        restoreFailure = nil
        isRestoring = true
        defer { isRestoring = false }

        let didRestore = await service.restore()
        isPremium = entitlements.isPremiumUnlocked
        Analytics.track(.restore(result: didRestore ? "restored" : (service.purchaseError == nil ? "nothing" : "failed")))

        if didRestore {
            restoreMessage = String(localized: "Your purchase has been restored.")
        } else if let failure = service.purchaseError {
            restoreFailure = failure
        } else {
            restoreMessage = String(localized: "No previous purchase found on this Apple Account.")
        }
    }

    public func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        openURL(url)
    }

    public func open(_ url: URL) {
        openURL(url)
    }
}
