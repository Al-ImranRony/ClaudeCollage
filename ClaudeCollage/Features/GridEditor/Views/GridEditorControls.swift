//
//  GridEditorControls.swift
//  ClaudeCollage
//
//  Step 01 — the bottom-bar controls for the grid editor: a horizontal layout
//  picker and a horizontal background-colour picker, both UICollectionViews
//  with UICollectionViewCompositionalLayout (per the plan's UIKit strategy).
//

import UIKit

// MARK: - Layout picker

final class LayoutPickerView: UIView {

    var onSelect: ((GridTemplate) -> Void)?

    private let templates: [GridTemplate]
    private var selected: GridTemplate
    private lazy var collectionView = makeCollectionView()

    init(templates: [GridTemplate] = GridTemplate.allCases, selected: GridTemplate) {
        self.templates = templates
        self.selected = selected
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSelected(_ template: GridTemplate) {
        guard template != selected else { return }
        selected = template
        collectionView.reloadData()
    }

    private func setup() {
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 76),
        ])
    }

    private func makeCollectionView() -> UICollectionView {
        var config = UICollectionLayoutListConfiguration(appearance: .plain)
        config.showsSeparators = false
        _ = config

        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(60), heightDimension: .absolute(60))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(60), heightDimension: .absolute(60)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.register(LayoutSchematicCell.self, forCellWithReuseIdentifier: LayoutSchematicCell.reuseID)
        return view
    }
}

extension LayoutPickerView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        templates.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(
            withReuseIdentifier: LayoutSchematicCell.reuseID, for: indexPath
        )
        if let schematic = cell as? LayoutSchematicCell {
            let template = templates[indexPath.item]
            schematic.configure(with: template, isSelected: template == selected)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let template = templates[indexPath.item]
        setSelected(template)
        onSelect?(template)
    }
}

/// Draws a small schematic of the grid layout. Rendering happens in
/// `draw(rect:)` — no per-layout subview churn during scrolling.
final class LayoutSchematicCell: UICollectionViewCell {
    static let reuseID = "LayoutSchematicCell"

    private let schematic = SchematicView()

    override init(frame: CGRect) {
        super.init(frame: frame)
        schematic.translatesAutoresizingMaskIntoConstraints = false
        schematic.layer.cornerRadius = 10
        schematic.layer.borderWidth = 2
        schematic.backgroundColor = .secondarySystemBackground
        schematic.isOpaque = false
        contentView.addSubview(schematic)
        NSLayoutConstraint.activate([
            schematic.topAnchor.constraint(equalTo: contentView.topAnchor),
            schematic.bottomAnchor.constraint(equalTo: contentView.bottomAnchor),
            schematic.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            schematic.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(with template: GridTemplate, isSelected: Bool) {
        schematic.backgroundColor = isSelected ? .tertiarySystemFill : .secondarySystemBackground
        schematic.layer.borderColor = (isSelected ? UIColor.tintColor : UIColor.separator).cgColor
        schematic.template = template
    }

    /// A UIView that draws the grid cells for a template in `draw(rect:)`.
    private final class SchematicView: UIView {
        var template: GridTemplate = .oneCell {
            didSet { if template != oldValue { setNeedsDisplay() } }
        }

        override func draw(_ rect: CGRect) {
            let area = bounds.insetBy(dx: 10, dy: 10)
            guard area.width > 0, area.height > 0 else { return }
            UIColor.tintColor.withAlphaComponent(0.55).setFill()
            for cell in template.normalizedCells {
                let path = UIBezierPath(
                    roundedRect: CGRect(
                        x: area.minX + cell.minX * area.width + 1,
                        y: area.minY + cell.minY * area.height + 1,
                        width: cell.width * area.width - 2,
                        height: cell.height * area.height - 2
                    ),
                    cornerRadius: 2
                )
                path.fill()
            }
        }
    }
}

// MARK: - Background picker

final class BackgroundPickerView: UIView {

    var onSelect: ((CollageBackground) -> Void)?

    private let backgrounds: [CollageBackground]
    private var selected: CollageBackground
    private lazy var collectionView = makeCollectionView()

    init(backgrounds: [CollageBackground] = CollageBackground.palette, selected: CollageBackground) {
        self.backgrounds = backgrounds
        self.selected = selected
        super.init(frame: .zero)
        setup()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func setSelected(_ background: CollageBackground) {
        guard background != selected else { return }
        selected = background
        collectionView.reloadData()
    }

    private func setup() {
        addSubview(collectionView)
        collectionView.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            collectionView.topAnchor.constraint(equalTo: topAnchor),
            collectionView.bottomAnchor.constraint(equalTo: bottomAnchor),
            collectionView.leadingAnchor.constraint(equalTo: leadingAnchor),
            collectionView.trailingAnchor.constraint(equalTo: trailingAnchor),
            heightAnchor.constraint(equalToConstant: 56),
        ])
    }

    private func makeCollectionView() -> UICollectionView {
        let item = NSCollectionLayoutItem(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(40), heightDimension: .absolute(40))
        )
        let group = NSCollectionLayoutGroup.horizontal(
            layoutSize: NSCollectionLayoutSize(widthDimension: .absolute(40), heightDimension: .absolute(40)),
            subitems: [item]
        )
        let section = NSCollectionLayoutSection(group: group)
        section.orthogonalScrollingBehavior = .continuous
        section.interGroupSpacing = 12
        section.contentInsets = NSDirectionalEdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16)
        let layout = UICollectionViewCompositionalLayout(section: section)

        let view = UICollectionView(frame: .zero, collectionViewLayout: layout)
        view.backgroundColor = .clear
        view.showsHorizontalScrollIndicator = false
        view.dataSource = self
        view.delegate = self
        view.register(SwatchCell.self, forCellWithReuseIdentifier: SwatchCell.reuseID)
        return view
    }
}

extension BackgroundPickerView: UICollectionViewDataSource, UICollectionViewDelegate {
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        backgrounds.count
    }

    func collectionView(
        _ collectionView: UICollectionView,
        cellForItemAt indexPath: IndexPath
    ) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCell(withReuseIdentifier: SwatchCell.reuseID, for: indexPath)
        if let swatch = cell as? SwatchCell {
            let background = backgrounds[indexPath.item]
            swatch.configure(color: UIColor(background: background), isSelected: background == selected)
        }
        return cell
    }

    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        let background = backgrounds[indexPath.item]
        setSelected(background)
        onSelect?(background)
    }
}

final class SwatchCell: UICollectionViewCell {
    static let reuseID = "SwatchCell"

    override init(frame: CGRect) {
        super.init(frame: frame)
        contentView.layer.cornerRadius = 20
        contentView.layer.borderWidth = 1
        contentView.layer.borderColor = UIColor.separator.cgColor
        contentView.clipsToBounds = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    func configure(color: UIColor, isSelected: Bool) {
        contentView.backgroundColor = color
        contentView.layer.borderWidth = isSelected ? 3 : 1
        contentView.layer.borderColor = (isSelected ? UIColor.tintColor : UIColor.separator).cgColor
    }
}
