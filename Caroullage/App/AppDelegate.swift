//
//  AppDelegate.swift
//  Caroullage
//
//  UIKit lifecycle entry point. Programmatic — no storyboard.
//  See Step 00 — Project Setup.
//
//  Home retention, phase 1: also the notification centre's delegate, so a
//  tapped reminder opens what it was about. The payload carries a `DeepLink`
//  URL and nothing else, which keeps this class as ignorant of navigation as
//  the scene delegate is.
//

import UIKit
import UserNotifications

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureAppearance()
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // MARK: UISceneSession Lifecycle

    func application(
        _ application: UIApplication,
        configurationForConnecting connectingSceneSession: UISceneSession,
        options: UIScene.ConnectionOptions
    ) -> UISceneConfiguration {
        UISceneConfiguration(name: "Default Configuration", sessionRole: connectingSceneSession.role)
    }

    // MARK: - Private

    private func configureAppearance() {
        // Global UIKit appearance — kept minimal in Step 00.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}

// MARK: - Notifications

extension AppDelegate: UNUserNotificationCenterDelegate {

    /// The key a scheduled reminder stores its `DeepLink` URL under.
    /// `nonisolated`: a constant, read by the nonisolated notification callback.
    nonisolated static let deepLinkUserInfoKey = "deepLink"

    /// A reminder that fires while the app is open still shows, as a banner:
    /// the user asked for it in Settings, and a silent drop would make the
    /// toggle look broken.
    // The completion-handler forms, and `nonisolated`: the async forms of these
    // requirements are called off the main actor with non-Sendable arguments,
    // which Swift 6 rejects for a `@MainActor` delegate. Everything the app
    // needs is read here into plain values before hopping to the main actor.
    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .list, .sound])
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let request = response.notification.request
        let identifier = request.identifier
        let raw = request.content.userInfo[Self.deepLinkUserInfoKey] as? String
        completionHandler()
        guard let raw, let url = URL(string: raw), let link = DeepLink.parse(url) else { return }
        Task { @MainActor in
            Analytics.track(.reminderOpened(kind: identifier))
            IntentRouter.shared.send(link.request)
        }
    }
}
