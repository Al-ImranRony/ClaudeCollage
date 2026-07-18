//
//  AppCoordinator.swift
//  ClaudeCollage
//
//  Root navigation coordinator (MVVM-C). Owns the root UINavigationController
//  and the ProjectStore, and routes between the home gallery and the grid
//  editor. SwiftUI screens (none yet in Step 01) would be presented here via
//  UIHostingController.
//

import UIKit
import SwiftData
import SwiftUI

@MainActor
final class AppCoordinator {

    private let navigationController: UINavigationController
    private let store: ProjectStore
    private weak var homeViewController: HomeViewController?
    /// Retains the panoramic PHPicker delegate for the life of the pick.
    private var panoramicPicker: PanoramicSourcePicker?

    init(navigationController: UINavigationController, container: ModelContainer) {
        self.navigationController = navigationController
        self.store = ProjectStore(container: container)
    }

    func start() {
        let home = HomeViewController()
        home.summariesProvider = { [weak self] in self?.store.listSummaries() ?? [] }
        home.onNewProject = { [weak self] in self?.startNewGridProject() }
        home.onNewFreeform = { [weak self] size in self?.startFreeformProject(size: size) }
        home.onBrowseTemplates = { [weak self] in self?.showTemplateGallery() }
        home.onNewCarousel = { [weak self] in self?.startCarousel() }
        home.onOpenProject = { [weak self] id in self?.openProject(id: id) }
        home.onDeleteProject = { [weak self] id in self?.store.delete(id: id) }
        homeViewController = home
        navigationController.setViewControllers([home], animated: false)
    }

    // MARK: - Routing

    private func startNewGridProject() {
        let viewModel = GridEditorViewModel()
        attachAutosave(to: viewModel)
        // Persist immediately so the project appears in the gallery on return.
        store.save(viewModel)
        pushEditor(with: viewModel)
    }

    /// Starts a blank collage on a user-defined canvas size (Step 03a slice 7).
    /// One full-bleed photo cell on a `.template` layout, so it inherits the whole
    /// editor stack (photos, text, stickers, snap guides, zoom, export) at an
    /// arbitrary aspect ratio.
    private func startFreeformProject(size: CGSize) {
        let clamped = CGSize(
            width: min(max(size.width.rounded(), 100), 4000),
            height: min(max(size.height.rounded(), 100), 4000)
        )
        let ratio = "\(Int(clamped.width)):\(Int(clamped.height))"
        let layout = CollageLayout.template(TemplateLayout(
            templateID: "freeform",
            name: "Freeform",
            aspectRatio: ratio,
            cells: [TemplateLayoutCell(frame: CGRect(x: 0, y: 0, width: 1, height: 1))]
        ))
        let state = GridEditorState(layout: layout, borderWidth: 0, background: .white)
        let viewModel = GridEditorViewModel(canvasSize: clamped, state: state)
        attachAutosave(to: viewModel)
        store.save(viewModel)
        pushEditor(with: viewModel)
    }

    /// Presents the SwiftUI carousel type selector; the chosen `CarouselStartConfig`
    /// is turned into frames (via the slice-3 builders) and pushed into the carousel
    /// editor. Panoramic first picks a wide source photo to split.
    private func startCarousel() {
        let selector = CarouselTypeSelectorView(
            onCreate: { [weak self] config in
                self?.navigationController.dismiss(animated: true) {
                    self?.beginCarousel(config: config)
                }
            },
            onCancel: { [weak self] in self?.navigationController.dismiss(animated: true) }
        )
        let host = UIHostingController(rootView: selector)
        host.view.accessibilityIdentifier = "carouselTypeSelector"
        navigationController.present(host, animated: true)
    }

    private func beginCarousel(config: CarouselStartConfig) {
        let canvasSize = CanvasSize.size(forAspectRatio: config.aspectRatio)
        let service = CarouselService()
        switch config.type {
        case .matched, .scrollThrough:
            let frames = service.blankCarousel(
                type: config.type, frameCount: config.frameCount, aspectRatio: config.aspectRatio)
            presentCarouselEditor(frames: frames, images: [:], canvasSize: canvasSize, type: config.type)
        case .gridPreview:
            // v1 seeds a default 4-up grid; picking an existing grid project as the
            // source is a follow-up. Frame count derives from the grid.
            let grid = GridEditorState(template: .fourSquare)
            let frames = service.buildGridPreviewCarousel(from: grid, aspectRatio: config.aspectRatio)
            presentCarouselEditor(frames: frames, images: [:], canvasSize: canvasSize, type: .gridPreview)
        case .panoramic:
            pickPanoramicSource(config: config, canvasSize: canvasSize)
        }
    }

    private func pickPanoramicSource(config: CarouselStartConfig, canvasSize: CGSize) {
        let picker = PanoramicSourcePicker { [weak self] image in
            guard let self else { return }
            self.panoramicPicker = nil
            guard let image else { return }
            let build = CarouselService().buildPanoramicCarousel(
                from: image, frameCount: config.frameCount, axis: config.splitAxis,
                aspectRatio: config.aspectRatio)
            self.presentCarouselEditor(
                frames: build.frames, images: build.images, canvasSize: canvasSize, type: .panoramic)
        }
        panoramicPicker = picker
        navigationController.present(picker.makePicker(), animated: true)
    }

    private func presentCarouselEditor(
        frames: [CarouselFrame], images: [UUID: CGImage], canvasSize: CGSize, type: CarouselType
    ) {
        let viewModel = CarouselEditorViewModel(
            frames: frames, images: images, canvasSize: canvasSize, carouselType: type)
        attachCarouselAutosave(to: viewModel)
        store.saveCarousel(viewModel)   // persist immediately so it lands on Home
        presentCarouselEditor(viewModel: viewModel)
    }

    private func presentCarouselEditor(viewModel: CarouselEditorViewModel) {
        let editor = CarouselEditorViewController(viewModel: viewModel)
        editor.onEditFrame = { [weak self] frameVM in self?.pushEditor(with: frameVM) }
        navigationController.pushViewController(editor, animated: true)
    }

    private func attachCarouselAutosave(to viewModel: CarouselEditorViewModel) {
        viewModel.onCommit = { [weak self] viewModel in
            self?.store.scheduleSaveCarousel(viewModel)
        }
    }

    private func showTemplateGallery() {
        let gallery = TemplateGalleryViewController(service: .shared)
        gallery.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }
        navigationController.pushViewController(gallery, animated: true)
    }

    /// Opens a (free or unlocked) template in the editor. Templates that exactly
    /// tile a stock grid open as that grid (so the layout picker highlights it);
    /// everything else opens as a `.template` layout with the authored geometry.
    /// Text/sticker/art zones are overlays owned by later 03a slices — today
    /// only the photo zones are editable.
    private func openTemplate(_ template: CollageTemplate) {
        let layout: CollageLayout
        if let grid = TemplateService.gridTemplate(matching: template) {
            layout = .grid(grid)
        } else {
            let templateLayout = TemplateService.editorLayout(for: template)
            guard !templateLayout.cells.isEmpty else {
                // No photo zones at all (e.g. a text-only design) — nothing the
                // editor can do with it until the text-zone slice lands.
                let alert = UIAlertController(
                    title: "Coming Soon",
                    message: "This template has no photo areas yet supported by the editor. Text and sticker editing arrive in an upcoming update.",
                    preferredStyle: .alert
                )
                alert.addAction(UIAlertAction(title: "OK", style: .default))
                navigationController.present(alert, animated: true)
                return
            }
            layout = .template(templateLayout)
        }

        // Text + sticker zones become editable overlays layered on the same editor
        // (Step 03a slices 5–6). Their styling / symbols + normalized frames come
        // from the parser and the sticker catalog.
        let state = GridEditorState(
            layout: layout,
            borderWidth: template.cells.first.map { max($0.borderWidth, 0) } ?? 8,
            background: template.background,
            textOverlays: template.cells.compactMap(\.textStyle),
            stickerOverlays: TemplateService.stickerOverlays(for: template)
        )
        let viewModel = GridEditorViewModel(
            canvasSize: CanvasSize.size(forAspectRatio: template.canvasAspectRatio),
            state: state
        )
        attachAutosave(to: viewModel)
        store.save(viewModel)
        pushEditor(with: viewModel)
    }

    private func openProject(id: UUID) {
        // Carousel projects resume into the carousel editor; everything else is a
        // grid/template/polygon project in the grid editor.
        if let carouselVM = store.loadCarouselViewModel(id: id) {
            attachCarouselAutosave(to: carouselVM)
            presentCarouselEditor(viewModel: carouselVM)
            return
        }
        guard let viewModel = store.loadViewModel(id: id) else { return }
        attachAutosave(to: viewModel)
        pushEditor(with: viewModel)
    }

    private func pushEditor(with viewModel: GridEditorViewModel) {
        let editor = GridEditorViewController(viewModel: viewModel)
        navigationController.pushViewController(editor, animated: true)
    }

    private func attachAutosave(to viewModel: GridEditorViewModel) {
        viewModel.onCommit = { [weak self] viewModel in
            self?.store.scheduleSave(viewModel)
        }
    }
}
