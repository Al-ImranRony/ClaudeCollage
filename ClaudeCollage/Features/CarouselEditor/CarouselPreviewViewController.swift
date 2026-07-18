//
//  CarouselPreviewViewController.swift
//  ClaudeCollage
//
//  Step 03b slice 6 — the full-screen swipe-through preview. A UIPageViewController
//  (.scroll) gives native Instagram-style paging physics; each page shows one
//  rendered frame with an optional safe-zone overlay. Chrome (close, frame counter,
//  safe-zone menu, export, page dots) toggles on tap. The safe-zone dimming is
//  preview-only and never exported.
//

import UIKit

final class CarouselPreviewViewController: UIViewController {

    /// Wired by the editor to run the real image-set export (full-resolution). When
    /// nil, the export button shows a coming-soon notice.
    var onExport: (() -> Void)?

    private let images: [UIImage?]
    private let aspectRatio: CGFloat          // width / height
    private var currentIndex: Int
    private var safeZone: SafeZonePreset = .none
    private var chromeHidden = false

    private lazy var pageController = UIPageViewController(
        transitionStyle: .scroll, navigationOrientation: .horizontal)

    private let counterLabel = UILabel()
    private let pageControl = UIPageControl()
    private let topBar = UIView()
    private let bottomBar = UIView()
    private lazy var safeZoneButton = UIButton(type: .system)

    // MARK: - Init

    init(images: [UIImage?], aspectRatio: CGFloat, startIndex: Int) {
        self.images = images
        self.aspectRatio = aspectRatio > 0 ? aspectRatio : 1
        self.currentIndex = min(max(startIndex, 0), max(images.count - 1, 0))
        super.init(nibName: nil, bundle: nil)
        modalPresentationStyle = .fullScreen
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    // MARK: - Lifecycle

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        view.accessibilityIdentifier = "carouselPreview"
        setupPageController()
        setupChrome()
        updateCounter()

        let tap = UITapGestureRecognizer(target: self, action: #selector(toggleChrome))
        tap.delegate = self
        view.addGestureRecognizer(tap)
    }

    // MARK: - Setup

    private func setupPageController() {
        pageController.dataSource = self
        pageController.delegate = self
        addChild(pageController)
        pageController.view.frame = view.bounds
        pageController.view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        view.addSubview(pageController.view)
        pageController.didMove(toParent: self)
        if let first = page(at: currentIndex) {
            pageController.setViewControllers([first], direction: .forward, animated: false)
        }
    }

    private func setupChrome() {
        for bar in [topBar, bottomBar] {
            bar.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(bar)
        }

        let close = UIButton(type: .system)
        close.setImage(UIImage(systemName: "xmark"), for: .normal)
        close.tintColor = .white
        close.accessibilityIdentifier = "previewCloseButton"
        close.accessibilityLabel = "Close"
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)
        close.translatesAutoresizingMaskIntoConstraints = false

        counterLabel.textColor = .white
        counterLabel.font = Theme.Typography.subheadline
        counterLabel.textAlignment = .center
        counterLabel.accessibilityIdentifier = "previewCounter"
        counterLabel.translatesAutoresizingMaskIntoConstraints = false

        safeZoneButton.setImage(UIImage(systemName: "rectangle.dashed"), for: .normal)
        safeZoneButton.tintColor = .white
        safeZoneButton.accessibilityIdentifier = "previewSafeZoneButton"
        safeZoneButton.accessibilityLabel = "Safe Zone"
        safeZoneButton.showsMenuAsPrimaryAction = true
        safeZoneButton.menu = makeSafeZoneMenu()
        safeZoneButton.translatesAutoresizingMaskIntoConstraints = false

        let export = UIButton(type: .system)
        export.setImage(UIImage(systemName: "square.and.arrow.up"), for: .normal)
        export.tintColor = .white
        export.accessibilityIdentifier = "previewExportButton"
        export.accessibilityLabel = "Export"
        export.addTarget(self, action: #selector(exportTapped), for: .touchUpInside)
        export.translatesAutoresizingMaskIntoConstraints = false

        for control in [close, counterLabel, safeZoneButton, export] {
            topBar.addSubview(control)
        }

        pageControl.numberOfPages = images.count
        pageControl.currentPage = currentIndex
        pageControl.accessibilityIdentifier = "previewPageControl"
        pageControl.isUserInteractionEnabled = false
        pageControl.translatesAutoresizingMaskIntoConstraints = false
        bottomBar.addSubview(pageControl)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            topBar.topAnchor.constraint(equalTo: guide.topAnchor),
            topBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            topBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            topBar.heightAnchor.constraint(equalToConstant: 48),

            close.leadingAnchor.constraint(equalTo: topBar.leadingAnchor, constant: 16),
            close.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            counterLabel.centerXAnchor.constraint(equalTo: topBar.centerXAnchor),
            counterLabel.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            export.trailingAnchor.constraint(equalTo: topBar.trailingAnchor, constant: -16),
            export.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),
            safeZoneButton.trailingAnchor.constraint(equalTo: export.leadingAnchor, constant: -20),
            safeZoneButton.centerYAnchor.constraint(equalTo: topBar.centerYAnchor),

            bottomBar.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            bottomBar.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            bottomBar.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            bottomBar.heightAnchor.constraint(equalToConstant: 40),
            pageControl.centerXAnchor.constraint(equalTo: bottomBar.centerXAnchor),
            pageControl.centerYAnchor.constraint(equalTo: bottomBar.centerYAnchor),
        ])
    }

    private func makeSafeZoneMenu() -> UIMenu {
        let actions = SafeZonePreset.allCases.map { preset in
            UIAction(title: preset.displayName,
                     state: preset == safeZone ? .on : .off) { [weak self] _ in
                self?.applySafeZone(preset)
            }
        }
        return UIMenu(title: "Safe Zone", children: actions)
    }

    // MARK: - Pages

    private func page(at index: Int) -> CarouselPreviewPageViewController? {
        guard images.indices.contains(index) else { return nil }
        let page = CarouselPreviewPageViewController(
            index: index, image: images[index], aspectRatio: aspectRatio)
        page.apply(safeZone: safeZone)
        return page
    }

    private func applySafeZone(_ preset: SafeZonePreset) {
        safeZone = preset
        safeZoneButton.menu = makeSafeZoneMenu()
        (pageController.viewControllers?.first as? CarouselPreviewPageViewController)?.apply(safeZone: preset)
    }

    private func updateCounter() {
        counterLabel.text = "\(currentIndex + 1) / \(images.count)"
        pageControl.currentPage = currentIndex
    }

    // MARK: - Actions

    @objc private func closeTapped() { dismiss(animated: true) }

    @objc private func exportTapped() {
        guard let onExport else {
            let alert = UIAlertController(
                title: "Export", message: "Export isn't available here.", preferredStyle: .alert)
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            present(alert, animated: true)
            return
        }
        // Hand back to the editor (which has the view model + full-res renderer).
        dismiss(animated: true) { onExport() }
    }

    @objc private func toggleChrome() {
        chromeHidden.toggle()
        UIView.animate(withDuration: Theme.Motion.quick) {
            self.topBar.alpha = self.chromeHidden ? 0 : 1
            self.bottomBar.alpha = self.chromeHidden ? 0 : 1
        }
    }
}

// MARK: - Page data source / delegate

extension CarouselPreviewViewController: UIPageViewControllerDataSource, UIPageViewControllerDelegate {

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerBefore viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? CarouselPreviewPageViewController else { return nil }
        return self.page(at: page.index - 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            viewControllerAfter viewController: UIViewController) -> UIViewController? {
        guard let page = viewController as? CarouselPreviewPageViewController else { return nil }
        return self.page(at: page.index + 1)
    }

    func pageViewController(_ pageViewController: UIPageViewController,
                            didFinishAnimating finished: Bool,
                            previousViewControllers: [UIViewController],
                            transitionCompleted completed: Bool) {
        guard completed,
              let page = pageViewController.viewControllers?.first as? CarouselPreviewPageViewController
        else { return }
        currentIndex = page.index
        updateCounter()
    }
}

// MARK: - UIGestureRecognizerDelegate

extension CarouselPreviewViewController: UIGestureRecognizerDelegate {
    // The tap-to-toggle-chrome recognizer must not swallow taps on the chrome buttons.
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldReceive touch: UITouch) -> Bool {
        !(touch.view is UIControl)
    }
}

// MARK: - One preview page

final class CarouselPreviewPageViewController: UIViewController {

    let index: Int
    private let frameImage: UIImage?
    private let aspectRatio: CGFloat
    private let imageView = UIImageView()
    private let overlay = SafeZoneOverlayView()

    init(index: Int, image: UIImage?, aspectRatio: CGFloat) {
        self.index = index
        self.frameImage = image
        self.aspectRatio = aspectRatio
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let container = UIView()
        container.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(container)

        imageView.image = frameImage
        imageView.contentMode = .scaleAspectFill
        imageView.clipsToBounds = true
        imageView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(imageView)

        overlay.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(overlay)

        let guide = view.safeAreaLayoutGuide
        let maxWidth = container.widthAnchor.constraint(equalTo: view.widthAnchor)
        maxWidth.priority = .defaultHigh
        let maxHeight = container.heightAnchor.constraint(equalTo: guide.heightAnchor)
        maxHeight.priority = .defaultHigh

        NSLayoutConstraint.activate([
            container.centerXAnchor.constraint(equalTo: view.centerXAnchor),
            container.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            container.widthAnchor.constraint(equalTo: container.heightAnchor, multiplier: aspectRatio),
            container.widthAnchor.constraint(lessThanOrEqualTo: view.widthAnchor),
            container.heightAnchor.constraint(lessThanOrEqualTo: guide.heightAnchor),
            maxWidth, maxHeight,

            imageView.topAnchor.constraint(equalTo: container.topAnchor),
            imageView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            imageView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            imageView.bottomAnchor.constraint(equalTo: container.bottomAnchor),

            overlay.topAnchor.constraint(equalTo: container.topAnchor),
            overlay.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            overlay.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])
    }

    func apply(safeZone: SafeZonePreset) {
        overlay.preset = safeZone
    }
}
