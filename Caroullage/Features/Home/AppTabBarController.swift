//
//  AppTabBarController.swift
//  Caroullage
//
//  Step 04.5 batch C — the app's root shell.
//
//  Module selection used to be five UIBarButtonItems crammed into the Home nav
//  bar. It is now a four-item bottom tab bar with a floating "Start Editing"
//  button sitting clear above it:
//
//                        (+)
//      Home | Templates | Projects | Carousel
//
//  Each tab owns its own UINavigationController, so pushing an editor keeps that
//  tab's back stack intact. Editors set `hidesBottomBarWhenPushed`, so the bar is
//  gone while editing and their bottom controls keep the full safe area.
//
//  The "+" is not a tab and no longer notches into the bar, so no placeholder is
//  needed to hold a centre slot open — all four items are real and evenly spread.
//  It is available from every tab: starting a collage should never require going
//  back to Home first. It lives in a hit-test-passthrough container so only the
//  button itself takes touches; everything around it reaches the content below.
//

import UIKit

@MainActor
final class AppTabBarController: UITabBarController {

    /// Tapped the floating "Start Editing" button.
    var onStartEditing: (() -> Void)?
    /// Called once, after the shell is actually on screen. Anything presented
    /// from `AppCoordinator.start()` would otherwise be presenting from a view
    /// controller that is not yet in a window, which UIKit drops on the floor.
    var onFirstAppearance: (() -> Void)?
    private var didReportFirstAppearance = false

    private let plusContainer = PassthroughView()
    private let plusButton = GradientLayerButton(type: .custom)

    private let diameter: CGFloat = 56
    /// Gap between the bottom of the button and the top of the tab bar. Small
    /// enough to read as one control cluster, large enough that the button is
    /// clearly floating above the bar rather than notched into it.
    private let barGap: CGFloat = 10

    /// Vertical space a tab root must leave free so its content can scroll clear
    /// of the button instead of being covered — and, worse, having its taps eaten.
    private var plusClearance: CGFloat { diameter + barGap }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didReportFirstAppearance else { return }
        didReportFirstAppearance = true
        onFirstAppearance?()
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        delegate = self
        configureAppearance()
        setupPlusButton()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        // Fully above the bar, not notched into it.
        plusContainer.frame = CGRect(
            x: 0,
            y: tabBar.frame.minY - diameter - barGap,
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

    /// Shown on every tab — starting a collage should never require switching to
    /// Home first — but never over a pushed editor.
    ///
    /// It lives on the tab bar CONTROLLER's view rather than on the bar, so
    /// `hidesBottomBarWhenPushed` slides the bar away without touching it; left
    /// alone it hovered over editors, on top of their bottom controls.
    ///
    /// Keyed off navigation stack depth rather than the bar's frame: the frame is
    /// mid-animation at the moment we need the answer, whereas the stack has
    /// already been updated by `willShow`.
    private func updatePlusVisibility() {
        plusContainer.isHidden = !isPlusVisible
    }

    private var isPlusVisible: Bool {
        guard let nav = selectedViewController as? UINavigationController else { return false }
        return nav.viewControllers.count == 1
    }

    // MARK: - Setup

    /// Wraps each root in its own navigation controller. All items are real — the
    /// "+" sits above the bar rather than inside it, so nothing holds a slot open.
    func setTabs(_ roots: [(root: UIViewController, item: UITabBarItem)]) {
        let controllers: [UIViewController] = roots.map { entry in
            // Applied to the ROOT, not the nav: a pushed editor hides both the bar
            // and the "+", so it must not inherit the reserved space.
            entry.root.additionalSafeAreaInsets.bottom = plusClearance
            let nav = UINavigationController(rootViewController: entry.root)
            nav.tabBarItem = entry.item
            // Watched so the floating "+" disappears the moment an editor is pushed.
            nav.delegate = self
            return nav
        }

        setViewControllers(controllers, animated: false)
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

        // Tab labels are ~11pt, which is body text as far as contrast is
        // concerned, so the selected state uses `accentStrong` rather than the
        // identity orange — the latter is 3.1:1 on white.
        let item = UITabBarItemAppearance()
        item.normal.titleTextAttributes = [
            .font: Theme.Typography.caption,
            .foregroundColor: Theme.Color.textSecondary,
        ]
        item.normal.iconColor = Theme.Color.textSecondary
        item.selected.titleTextAttributes = [
            .font: Theme.Typography.caption,
            .foregroundColor: Theme.Color.accentStrong,
        ]
        item.selected.iconColor = Theme.Color.accentStrong
        appearance.stackedLayoutAppearance = item
        appearance.inlineLayoutAppearance = item
        appearance.compactInlineLayoutAppearance = item

        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        tabBar.tintColor = Theme.Color.accentStrong
        tabBar.unselectedItemTintColor = Theme.Color.textSecondary
        tabBar.accessibilityIdentifier = "mainTabBar"
    }

    private func setupPlusButton() {
        // The one hero surface in the shell, so it carries the brand gradient
        // rather than a flat fill. Running it `accentStrong → accent` keeps the
        // glyph clear of the pale end of the ramp, where white would be 2.2:1.
        plusButton.useBrandGradient()
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
        UIView.animate(withDuration: Theme.Motion.duration(Theme.Motion.quick)) {
            self.plusButton.transform = CGAffineTransform(scaleX: 0.92, y: 0.92)
        }
    }

    @objc private func plusReleased() {
        UIView.animate(
            withDuration: Theme.Motion.duration(Theme.Motion.standard), delay: 0,
            usingSpringWithDamping: Theme.Motion.effectiveSpringDamping,
            initialSpringVelocity: Theme.Motion.effectiveSpringVelocity
        ) {
            self.plusButton.transform = .identity
        }
    }
}

// MARK: - Delegate

extension AppTabBarController: UITabBarControllerDelegate {
    func tabBarController(
        _ tabBarController: UITabBarController, didSelect viewController: UIViewController
    ) {
        Haptics.selectionChanged()
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
        // These three checks are what `super.hitTest` does before it walks anything,
        // and overriding without them made the container claim touches even while
        // hidden: the editor's Border slider and Custom Shape button sit in exactly
        // the band the button occupies, so dragging the slider opened the Start
        // Editing sheet instead.
        guard !isHidden, alpha > 0.01, isUserInteractionEnabled else { return nil }

        for subview in subviews.reversed() where !subview.isHidden && subview.alpha > 0.01 {
            let local = convert(point, to: subview)
            if let hit = subview.hitTest(local, with: event) { return hit }
        }
        return nil
    }
}
