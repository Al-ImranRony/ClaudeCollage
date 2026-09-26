//
//  SceneDelegate.swift
//  Caroullage
//
//  Initializes UIWindow and hands control to AppCoordinator.
//
//  Home retention, phase 1: this is also where the app's URLs arrive. A widget
//  tile, the export Live Activity, a Spotlight result and a reminder tap all
//  land in one of the three routes below and are parsed by `DeepLink` into an
//  `IntentRouter` request — the same queue Siri uses — so cold launch and
//  warm launch behave identically and nothing here knows how to navigate.
//

import UIKit
import SwiftData

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {

    var window: UIWindow?
    private var appCoordinator: AppCoordinator?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }

        let window = UIWindow(windowScene: windowScene)
        let tabBarController = AppTabBarController()

        let container = ModelContainerFactory.makeShared()
        let coordinator = AppCoordinator(tabBarController: tabBarController, container: container)
        coordinator.start()

        AppAppearance.apply(to: window)
        window.rootViewController = tabBarController
        window.makeKeyAndVisible()

        Haptics.prepare()

        self.window = window
        self.appCoordinator = coordinator

        // A cold launch from a link arrives HERE, not in the two methods below.
        connectionOptions.urlContexts.forEach { route($0.url) }
        connectionOptions.userActivities.forEach(route)
        routeLaunchArgumentLink()
    }

    // MARK: - Deep links

    func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        URLContexts.forEach { route($0.url) }
    }

    func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        route(userActivity)
    }

    private func route(_ url: URL) {
        guard let link = DeepLink.parse(url) else { return }
        Analytics.track(.deepLinkOpened(kind: link.analyticsKind))
        IntentRouter.shared.send(link.request)
    }

    private func route(_ activity: NSUserActivity) {
        guard let link = DeepLink.parse(activity) else { return }
        Analytics.track(.deepLinkOpened(kind: link.analyticsKind))
        IntentRouter.shared.send(link.request)
    }

    /// `-deepLink caroullage://…` on the launch line — see `DevelopmentHooks`.
    private func routeLaunchArgumentLink() {
        guard let raw = DevelopmentHooks.launchDeepLink(),
              let url = URL(string: raw) else { return }
        route(url)
    }
}
