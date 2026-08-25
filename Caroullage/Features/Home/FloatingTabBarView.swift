//
//  FloatingTabBarView.swift
//  Caroullage
//
//  Step 06 UI pass — the shell's tab bar.
//
//  `UITabBar` cannot be a floating pill with a capsule behind the selected item,
//  and that shape is the difference between a shell that looks shipped and one
//  that looks like the default. So the bar is drawn here and the tab bar
//  controller keeps only the plumbing it is good at: a navigation stack per tab.
//
//  What that costs: selection, the selected trait for VoiceOver, and the tap
//  handling are ours now. What it buys: the bar floats clear of the screen edge,
//  the selected item sits in a tinted capsule, and the "Start Editing" pill can
//  overlap it as one cluster.
//

import UIKit

@MainActor
final class FloatingTabBarView: UIView {

    struct Item {
        let title: String
        let symbol: String
        let identifier: String
    }

    /// Tapped a tab. Not called for programmatic selection — that came from the
    /// controller, and reporting it back would loop.
    var onSelect: ((Int) -> Void)?

    private(set) var selectedIndex = 0
    private(set) var itemButtons: [UIButton] = []

    private let stack = UIStackView()
    private let capsule = UIView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    private func setup() {
        accessibilityIdentifier = "mainTabBar"
        backgroundColor = Theme.Color.surfaceRaised
        layer.cornerRadius = 30
        layer.cornerCurve = .continuous
        // The bar floats, so it needs its own separation from the content it
        // covers — a hairline border for light mode and a soft shadow for depth.
        layer.borderWidth = 1 / UIScreen.main.scale
        layer.borderColor = Theme.Color.separator.cgColor
        layer.shadowColor = UIColor.black.cgColor
        layer.shadowOpacity = 0.10
        layer.shadowRadius = 16
        layer.shadowOffset = CGSize(width: 0, height: 6)

        // A touch stronger than `accentSoft`: at 15% the capsule was invisible
        // against `surfaceRaised`, which left the selected tab looking like a
        // colour change rather than a place.
        capsule.backgroundColor = Theme.Color.accent.withAlphaComponent(0.22)
        capsule.layer.cornerRadius = 16
        capsule.layer.cornerCurve = .continuous
        capsule.isUserInteractionEnabled = false
        addSubview(capsule)

        stack.axis = .horizontal
        stack.distribution = .fillEqually
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.topAnchor.constraint(equalTo: topAnchor, constant: 6),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -6),
            stack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 8),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -8),
        ])

        registerForTraitChanges([UITraitUserInterfaceStyle.self]) { (view: Self, _) in
            view.layer.borderColor = Theme.Color.separator.cgColor
        }
    }

    // MARK: - Items

    func setItems(_ items: [Item]) {
        itemButtons.forEach { $0.removeFromSuperview() }
        itemButtons = items.enumerated().map { index, item in makeButton(item, index: index) }
        itemButtons.forEach(stack.addArrangedSubview)
        applySelection()
    }

    private func makeButton(_ item: Item, index: Int) -> UIButton {
        var config = UIButton.Configuration.plain()
        config.image = UIImage(
            systemName: item.symbol,
            withConfiguration: UIImage.SymbolConfiguration(pointSize: 15, weight: .semibold))
        config.imagePlacement = .top
        config.imagePadding = 3
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 4, bottom: 6, trailing: 4)
        config.attributedTitle = AttributedString(
            item.title, attributes: AttributeContainer([.font: Theme.Typography.tabLabel]))

        let button = UIButton(configuration: config, primaryAction: UIAction { [weak self] _ in
            guard let self else { return }
            self.select(index: index)
            Haptics.selectionChanged()
            self.onSelect?(index)
        })
        button.accessibilityIdentifier = item.identifier
        button.accessibilityLabel = item.title
        // The system bar gave items this for free; drawn by hand it has to be said.
        button.accessibilityTraits.insert(.button)
        return button
    }

    // MARK: - Selection

    /// Moves the selection without reporting it back to the controller.
    func select(index: Int) {
        guard itemButtons.indices.contains(index) else { return }
        selectedIndex = index
        applySelection()
    }

    private func applySelection() {
        for (index, button) in itemButtons.enumerated() {
            let isSelected = index == selectedIndex
            let colour = isSelected ? Theme.Color.accentStrong : Theme.Color.textSecondary
            button.configuration?.baseForegroundColor = colour
            if isSelected {
                button.accessibilityTraits.insert(.selected)
            } else {
                button.accessibilityTraits.remove(.selected)
            }
        }
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        // The stack lays its arranged views out during its own pass, which comes
        // after this one — without this the buttons are still at .zero and the
        // capsule is sized from nothing.
        stack.layoutIfNeeded()

        guard itemButtons.indices.contains(selectedIndex) else {
            capsule.isHidden = true
            return
        }
        capsule.isHidden = false
        // The button's frame is in the stack's space; the capsule is a sibling of
        // the stack, so it has to be converted or it lands 8pt off.
        let button = itemButtons[selectedIndex]
        let target = stack.convert(button.frame, to: self).insetBy(dx: 3, dy: 2)
        // Straight to the frame on first layout; animated afterwards, so the
        // capsule does not fly in from nothing when the bar first appears.
        if capsule.frame == .zero || Theme.Motion.isReduced {
            capsule.frame = target
        } else {
            UIView.animate(
                withDuration: Theme.Motion.duration(Theme.Motion.quick),
                delay: 0, options: [.beginFromCurrentState, .curveEaseOut]
            ) {
                self.capsule.frame = target
            }
        }
    }
}
