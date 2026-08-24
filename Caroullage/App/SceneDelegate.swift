//
//  SceneDelegate.swift
//  Caroullage
//
//  Initializes UIWindow and hands control to AppCoordinator.
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
    }
}
