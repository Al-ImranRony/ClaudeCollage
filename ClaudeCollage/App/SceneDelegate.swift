//
//  SceneDelegate.swift
//  ClaudeCollage
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
        let navigationController = UINavigationController()
        navigationController.navigationBar.prefersLargeTitles = true

        let container = ModelContainerFactory.makeShared()
        let coordinator = AppCoordinator(navigationController: navigationController, container: container)
        coordinator.start()

        window.rootViewController = navigationController
        window.makeKeyAndVisible()

        self.window = window
        self.appCoordinator = coordinator
    }
}
