//
//  AppTabBarController.swift
//  ClaudeCollage
//
//  Step 04.5 batch C — the app's root shell.
//
//  Module selection used to be five UIBarButtonItems crammed into the Home nav
//  bar. It is now a bottom tab bar with a floating "Start Editing" button:
//
//      Home | Templates | (+) | Projects | Carousel
//
//  Each tab owns its own UINavigationController, so pushing an editor keeps that
//  tab's back stack intact. Editors set `hidesBottomBarWhenPushed`, so the bar is
//  gone while editing and their bottom controls keep the full safe area.
//
//  The "+" is not a tab. UITabBarController spreads its items evenly, so a real
//  centred button would straddle two of them; instead a disabled placeholder tab
//  holds the middle slot open and the button floats above the gap in a
//  hit-test-passthrough container.
//

import UIKit

@MainActor
final class AppTabBarController: UITabBarController {

    /// Tapped the floating "Start Editing" button.
    var onStartEditing: (() -> Void)?

    /// Index of the disabled placeholder that reserves the centre slot.
    private static let placeholderIndex = 2

    private let plusContainer = PassthroughView()
    private let plusButton = UIButton(type: .custom)

    private let diameter: CGFloat = 60

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        configureAppearance()
        setupPlusButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Sits slightly proud of the bar, which is what reads as "floating".
        plusContainer.frame = CGRect(
            x: 0,
            y: tabBar.frame.minY - diameter / 2,
            width: view.bounds.width,
            height: diameter
        )
        plusButton.frame = CGRect(
            x: (view.bounds.width - diameter) / 2, y: 0, width: diameter, height: diameter
        )
        plusButton.layer.cornerRadius = diameter / 2
        updatePlusVisibility()
    }

    // MARK: - Floating button visibility

    /// The "+" belongs to Home only, and must never outlive the tab bar.
    ///
    /// It lives on the tab bar CONTROLLER's view rather than on the bar, so
    /// `hidesBottomBarWhenPushed` slides the bar away without touching it — it was
    /// left hovering over pushed editors, sitting on top of their bottom controls.
    ///
    /// Keyed off navigation stack depth rather than the bar's frame: the frame is
    /// mid-animation at the moment we need the answer, whereas the stack has
    /// already been updated by `willShow`.
    private func updatePlusVisibility() {
        plusContainer.isHidden = !isPlusVisible
    }

    private var isPlusVisible: Bool {
        guard selectedIndex == Self.homeIndex,
              let nav = selectedViewController as? UINavigationController
        else { return false }
        return nav.viewControllers.count == 1
    }

    private static let homeIndex = 0

    // MARK: - Setup

    /// Wraps each root in its own navigation controller and inserts the disabled
    /// placeholder that holds the centre slot open for the "+".
    func setTabs(_ roots: [(root: UIViewController, item: UITabBarItem)]) {
        var controllers: [UIViewController] = roots.map { entry in
            let nav = UINavigationController(rootViewController: entry.root)
            nav.tabBarItem = entry.item
            // Watched so the floating "+" disappears the moment an editor is pushed.
            nav.delegate = self
            return nav
        }

        let placeholder = UIViewController()
        placeholder.tabBarItem = UITabBarItem(title: nil, image: nil, tag: 0)
        placeholder.tabBarItem.isEnabled = false
        placeholder.tabBarItem.accessibilityIdentifier = "tabBarCentreSpacer"
        controllers.insert(placeholder, at: Self.placeholderIndex)

        setViewControllers(controllers, animated: false)
        // The placeholder must never be the initial selection.
        selectedIndex = 0
    }

    /// The navigation stack a newly created project should be pushed onto.
    var activeNavigationController: UINavigationController? {
        (selectedViewController as? UINavigationController) ?? viewControllers?
            .compactMap { $0 as? UINavigationController }.first
    }

    /// Selects a tab by its root view controller type, so the coordinator can send
    /// the user to Projects after finishing something without holding indexes.
    func selectTab(containing predicate: (UIViewController) -> Bool) {
        guard let controllers = viewControllers else { return }
        for (index, controller) in controllers.enumerated() {
            guard let nav = controller as? UINavigationController,
                  let root = nav.viewControllers.first, predicate(root) else { continue }
            selectedIndex = index
            return
        }
    }

    private func configureAppearance() {
        let appearance = UITabBarAppearance()
        appearance.configureWithDefaultBackground()
        appearance.backgroundColor = Theme.Color.surface
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = Theme.Color.accent
        tabBar.unselectedItemTintColor = Theme.Color.textSecondary
        tabBar.accessibilityIdentifier = "mainTabBar"
    }

    private func setupPlusButton() {
        plusButton.backgroundColor = Theme.Color.accent
        plusButton.tintColor = Theme.Color.textOnAccent
        plusButton.setImage(
            UIImage(systemName: "plus", withConfiguration:
                        UIImage.SymbolConfiguration(pointSize: 24, weight: .semibold)),
            for: .normal
        )
        plusButton.accessibilityIdentifier = "startEditingButton"
        plusButton.accessibilityLabel = "Start Editing"
        plusButton.layer.cornerCurve = .continuous
        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.22
        plusButton.layer.shadowRadius = 10
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        plusButton.addTarget(self, action: #selector(plusPressed), for: .touchDown)
        plusButton.addTarget(self, action: #selector(plusReleased),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])

        plusContainer.addSubview(plusButton)
        view.addSubview(plusContainer)
    }

    @objc private func plusTapped() {
        Haptics.tap()
        onStartEditing?()
    }

    @objc private func plusPressed() {
        UIView.animate(withDuration: Theme.Motion.quick) {
            self.plusButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc private func plusReleased() {
        UIView.animate(
            withDuration: Theme.Motion.standard, delay: 0,
            usingSpringWithDamping: Theme.Motion.springDamping,
            initialSpringVelocity: Theme.Motion.springVelocity
        ) {
            self.plusButton.transform = .identity
        }
    }
}

// MARK: - Delegate

extension AppTabBarController: UITabBarControllerDelegate {
    /// Belt-and-braces alongside `isEnabled = false`: the centre spacer is not a
    /// destination, so it must never become the selection.
    func tabBarController(
        _ tabBarController: UITabBarController, shouldSelect viewController: UIViewController
    ) -> Bool {
        viewControllers?.firstIndex(of: viewController) != Self.placeholderIndex
    }

    func tabBarController(
        _ tabBarController: UITabBarController, didSelect viewController: UIViewController
    ) {
        updatePlusVisibility()
    }
}

// MARK: - Child navigation

extension AppTabBarController: UINavigationControllerDelegate {
    /// Fires before the push/pop animation, by which point the stack has already
    /// changed — so the "+" leaves with the tab bar instead of lingering over the
    /// editor for the length of the transition.
    func navigationController(
        _ navigationController: UINavigationController,
        willShow viewController: UIViewController, animated: Bool
    ) {
        updatePlusVisibility()
    }
}

// MARK: - Passthrough container

/// Hosts the floating button without stealing touches. Anything outside the
/// button's own bounds falls through to the tab bar and content beneath, which a
/// plain full-width `UIView` would otherwise swallow.
private final class PassthroughView: UIView {
    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        for subview in subviews.reversed() {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local, with: event) { return hit }
        }
        return nil
    }
}
