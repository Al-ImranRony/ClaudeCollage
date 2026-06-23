//
//  AppDelegate.swift
//  ClaudeCollage
//
//  UIKit lifecycle entry point. Programmatic — no storyboard.
//  See Step 00 — Project Setup.
//

import UIKit
import FirebaseCore
import FirebaseCrashlytics
import TelemetryDeck

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        configureFirebase()
        configureTelemetryDeck()
        configureAppearance()
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

    private func configureFirebase() {
        // GoogleService-Info.plist is required at the project root before this runs in production.
        // For Debug builds without the plist we skip configuration silently.
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            #if DEBUG
            print("[ClaudeCollage] GoogleService-Info.plist missing — Firebase disabled in this build.")
            #endif
            return
        }
        FirebaseApp.configure()
        Crashlytics.crashlytics().setCrashlyticsCollectionEnabled(true)
    }

    private func configureTelemetryDeck() {
        // Replace with the real app ID once the TelemetryDeck app is provisioned.
        let appID = Bundle.main.object(forInfoDictionaryKey: "TelemetryDeckAppID") as? String ?? ""
        guard !appID.isEmpty else {
            #if DEBUG
            print("[ClaudeCollage] TelemetryDeck app ID missing — analytics disabled in this build.")
            #endif
            return
        }
        let config = TelemetryDeck.Config(appID: appID)
        TelemetryDeck.initialize(config: config)
    }

    private func configureAppearance() {
        // Global UIKit appearance — kept minimal in Step 00.
        let appearance = UINavigationBarAppearance()
        appearance.configureWithDefaultBackground()
        UINavigationBar.appearance().standardAppearance = appearance
        UINavigationBar.appearance().scrollEdgeAppearance = appearance
    }
}
