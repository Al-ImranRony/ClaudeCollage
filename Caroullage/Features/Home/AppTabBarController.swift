//
//  AppTabBarController.swift
//  Caroullage
//
//  Step 04.5 batch C — the app's root shell. Restyled in Step 06's UI pass.
//
//  Module selection used to be five UIBarButtonItems crammed into the Home nav
//  bar. It is now a floating pill bar with a wide "Start Editing" pill sitting
//  clear above it:
//
//               ( +  Start Editing )
//      ( Home | Templates | Projects | Carousel )
//
//  The system `UITabBar` is hidden and `FloatingTabBarView` draws the bar, which
//  is the only way to get a bar that floats clear of the screen edge with a
//  capsule behind the selected item. `UITabBarController` is still underneath,
//  because the thing it is genuinely good at — a navigation stack per tab — is
//  exactly what a hand-rolled shell gets wrong.
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

    private let shellContainer = PassthroughView()
    private let floatingBar = FloatingTabBarView()
    private let plusButton = GradientLayerButton(type: .custom)

    /// The pill's height, and the bar's. Both stay above the 44pt minimum touch
    /// target — the pill is 46 tall, and each tab item gets 44 of the bar's 56.
    private let plusHeight: CGFloat = 46
    private let barHeight: CGFloat = 56
    /// Gap between the pill and the bar. Small enough to read as one control
    /// cluster, large enough that the pill is clearly floating above the bar.
    private let barGap: CGFloat = 12
    /// Inset of the floating bar from the screen edges.
    private let barInset: CGFloat = 14

    /// Vertical space a tab root must leave free so its content can scroll clear
    /// of the cluster instead of being covered — and, worse, having its taps eaten.
    ///
    /// Includes the bar's own gap from the bottom edge and a margin above the
    /// pill, so the last row of a list clears the cluster instead of hiding
    /// under it.
    private var shellClearance: CGFloat { plusHeight + barGap + barHeight + 16 }

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
        setupShell()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()

        let width = view.bounds.width
        // Where a bottom bar belongs: its bottom edge just below the safe-area
        // line, which puts it ~28pt off the screen edge on a home-indicator
        // phone — clear of the indicator, and not floating in mid-air the way a
        // fully inset bar does. Devices without an indicator get a plain margin.
        let bottomInset = view.safeAreaInsets.bottom
        let bottomMargin = bottomInset > 0 ? bottomInset - 6 : 10
        let barY = view.bounds.height - bottomMargin - barHeight
        let plusY = barY - barGap - plusHeight

        shellContainer.frame = CGRect(
            x: 0, y: plusY, width: width, height: barY + barHeight - plusY)

        floatingBar.frame = CGRect(
            x: barInset, y: barY - plusY, width: width - barInset * 2, height: barHeight)
        floatingBar.layer.cornerRadius = barHeight / 2

        let plusWidth = min(width - barInset * 4, max(180, plusButton.intrinsicContentSize.width + 40))
        plusButton.frame = CGRect(
            x: (width - plusWidth) / 2, y: 0, width: plusWidth, height: plusHeight)
        plusButton.layer.cornerRadius = plusHeight / 2

        updateShellVisibility()
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
    private func updateShellVisibility() {
        shellContainer.isHidden = !isShellVisible
    }

    private var isShellVisible: Bool {
        guard let nav = selectedViewController as? UINavigationController else { return false }
        return nav.viewControllers.count == 1
    }

    // MARK: - Setup

    /// Wraps each root in its own navigation controller. All items are real — the
    /// "+" sits above the bar rather than inside it, so nothing holds a slot open.
    func setTabs(_ roots: [(root: UIViewController, item: FloatingTabBarView.Item)]) {
        let controllers: [UIViewController] = roots.map { entry in
            // Applied to the ROOT, not the nav: a pushed editor hides the whole
            // cluster, so it must not inherit the reserved space.
            entry.root.additionalSafeAreaInsets.bottom = shellClearance
            let nav = UINavigationController(rootViewController: entry.root)
            // The system item still exists — the hidden bar and the controller's
            // own bookkeeping read it — but nothing draws from it.
            // No accessibility identifier here: the hidden bar still publishes
            // its items, and two elements answering to "projectsTab" makes every
            // query ambiguous. Only the drawn bar's buttons are addressable.
            nav.tabBarItem = UITabBarItem(
                title: entry.item.title, image: UIImage(systemName: entry.item.symbol), tag: 0)
            // Watched so the floating "+" disappears the moment an editor is pushed.
            nav.delegate = self
            return nav
        }

        setViewControllers(controllers, animated: false)
        selectedIndex = 0

        floatingBar.setItems(roots.map(\.item))
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
        // The system bar is hidden, not restyled — `FloatingTabBarView` draws
        // what the user sees. The appearance below still runs so that anything
        // UIKit renders from the bar during a transition matches the theme
        // instead of flashing a default grey.
        tabBar.isHidden = true
        tabBar.accessibilityElementsHidden = true

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
    }

    private func setupShell() {
        floatingBar.onSelect = { [weak self] index in
            guard let self, self.selectedIndex != index else { return }
            self.selectedIndex = index
            self.updateShellVisibility()
        }
        shellContainer.addSubview(floatingBar)
        setupPlusButton()
        view.addSubview(shellContainer)
    }

    private func setupPlusButton() {
        // The one hero surface in the shell, so it carries the brand gradient
        // rather than a flat fill. Running it `accentStrong → accent` keeps the
        // glyph clear of the pale end of the ramp, where white would be 2.2:1.
        plusButton.useBrandGradient()
        plusButton.tintColor = Theme.Color.textOnAccent
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: "plus",
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .bold))
        config.imagePadding = 7
        config.attributedTitle = AttributedString(
            String(localized: "Start Editing"),
            attributes: AttributeContainer([.font: Theme.Typography.callout]))
        config.baseForegroundColor = Theme.Color.textOnAccent
        config.contentInsets = NSDirectionalEdgeInsets(top: 0, leading: 18, bottom: 0, trailing: 20)
        plusButton.configuration = config
        plusButton.accessibilityIdentifier = "startEditingButton"
        plusButton.accessibilityLabel = "Start Editing"
        plusButton.layer.cornerCurve = .continuous
        plusButton.layer.shadowColor = UIColor.black.cgColor
        plusButton.layer.shadowOpacity = 0.22
        plusButton.layer.shadowRadius = 10
        plusButton.layer.shadowOffset = CGSize(width: 0, height: 4)
        plusButton.addTarget(self, action: #selector(plusTapped), for: .touchUpInside)
        // A wide pill casts a heavier shadow than a small circle did, or it
        // looks pasted onto the bar rather than hovering over it.
        plusButton.layer.shadowOpacity = 0.26
        plusButton.addTarget(self, action: #selector(plusPressed), for: .touchDown)
        plusButton.addTarget(self, action: #selector(plusReleased),
                             for: [.touchUpInside, .touchUpOutside, .touchCancel])

        shellContainer.addSubview(plusButton)
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
        // Keeps the drawn bar in step with selection changes that did not come
        // from a tap — a deep link, or the coordinator sending the user to
        // Projects after a save.
        floatingBar.select(index: selectedIndex)
        updateShellVisibility()
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
        updateShellVisibility()
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
