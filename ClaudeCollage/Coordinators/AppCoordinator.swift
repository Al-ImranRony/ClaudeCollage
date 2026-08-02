//
//  AppCoordinator.swift
//  ClaudeCollage
//
//  Root navigation coordinator (MVVM-C). Owns the root `AppTabBarController` and
//  the ProjectStore, and routes between the tabs and every editor. SwiftUI screens
//  are presented here via UIHostingController.
//
//  Step 04.5 batch C moved the root from a single UINavigationController to a tab
//  bar. Every screen keeps the closure interface it already had — the closures are
//  rewired, not rewritten — so no editor changed. Pushes now target the SELECTED
//  tab's stack (`activeNavigationController`) instead of one global stack.
//

import UIKit
import SwiftData
import SwiftUI
import PhotosUI

@MainActor
final class AppCoordinator {

    private let tabBarController: AppTabBarController
    private let store: ProjectStore
    /// Retains the panoramic PHPicker delegate for the life of the pick.
    private var panoramicPicker: PanoramicSourcePicker?
    /// Retains the "+" flow's photo picker delegate for the life of the pick.
    private var startEditingPicker: StartEditingPhotoPicker?

    init(tabBarController: AppTabBarController, container: ModelContainer) {
        self.tabBarController = tabBarController
        self.store = ProjectStore(container: container)
    }

    func start() {
        let home = HomeViewController()
        home.featuredTemplatesProvider = { TemplateService.shared.templates }
        home.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }
        home.onBrowseTemplates = { [weak self] in self?.selectTemplatesTab() }
        home.onNewProject = { [weak self] in self?.startNewGridProject() }
        home.onNewPolygon = { [weak self] in self?.startNewPolygonProject() }
        home.onNewVideoCollage = { [weak self] in self?.startVideoCollage() }

        let templates = TemplateGalleryViewController(service: .shared)
        templates.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }

        let projects = ProjectsViewController()
        projects.summariesProvider = { [weak self] in self?.store.listSummaries() ?? [] }
        projects.onNewProject = { [weak self] in self?.startNewGridProject() }
        projects.onOpenProject = { [weak self] id in self?.openProject(id: id) }
        projects.onDeleteProject = { [weak self] id in self?.store.delete(id: id) }

        let carousel = CarouselStartViewController()
        carousel.onCreate = { [weak self] config in self?.beginCarousel(config: config) }

        tabBarController.setTabs([
            (home, tabItem("Home", "house.fill", "homeTab")),
            (templates, tabItem("Templates", "rectangle.3.group.fill", "templatesButton")),
            (projects, tabItem("Projects", "square.grid.2x2.fill", "projectsTab")),
            (carousel, tabItem("Carousel", "rectangle.stack.fill", "carouselButton")),
        ])
        tabBarController.onStartEditing = { [weak self] in self?.presentStartEditingSheet() }

        // Bundled templates back the Home strip; the gallery loads them too, but
        // Home is shown first so it cannot wait for that.
        _ = TemplateService.shared.loadBundledTemplates()
        home.reload()
    }

    private func tabItem(_ title: String, _ symbol: String, _ identifier: String) -> UITabBarItem {
        let item = UITabBarItem(title: title, image: UIImage(systemName: symbol), tag: 0)
        item.accessibilityIdentifier = identifier
        return item
    }

    // MARK: - Navigation helpers

    /// The stack a newly created project is pushed onto: whichever tab the user
    /// started from, so Back returns them where they were.
    private var navigationController: UINavigationController {
        tabBarController.activeNavigationController ?? UINavigationController()
    }

    private func selectTemplatesTab() {
        tabBarController.selectTab { $0 is TemplateGalleryViewController }
    }

    // MARK: - "Start Editing" (+)

    /// The floating "+" — the one place creation-with-a-choice begins.
    ///
    /// Grid vs Shapes vs Freeform is deliberately NOT asked here: pick photos and
    /// start editing, then swap layout from the editor's own Layout/Shape pickers.
    private func presentStartEditingSheet() {
        let sheet = UIAlertController(
            title: "Start Editing", message: nil, preferredStyle: .actionSheet)
        sheet.view.accessibilityIdentifier = "startEditingSheet"

        let image = UIAlertAction(title: "Image", style: .default) { [weak self] _ in
            self?.pickPhotosForNewCollage()
        }
        image.accessibilityIdentifier = "startEditingImage"
        let video = UIAlertAction(title: "Video", style: .default) { [weak self] _ in
            self?.startVideoCollage()
        }
        video.accessibilityIdentifier = "startEditingVideo"
        let canvas = UIAlertAction(title: "Custom Canvas", style: .default) { [weak self] _ in
            self?.promptForCustomCanvas()
        }
        canvas.accessibilityIdentifier = "startEditingCustomCanvas"

        sheet.addAction(image)
        sheet.addAction(video)
        sheet.addAction(canvas)
        sheet.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        // The "+" floats over the tab bar, so anchor the popover there on iPad.
        sheet.popoverPresentationController?.sourceView = tabBarController.view
        sheet.popoverPresentationController?.sourceRect = CGRect(
            x: tabBarController.view.bounds.midX, y: tabBarController.view.bounds.maxY - 90,
            width: 1, height: 1)
        tabBarController.present(sheet, animated: true)
    }

    /// Photos-first entry: pick up to nine images, then open a grid sized to fit
    /// them with every cell already filled.
    private func pickPhotosForNewCollage() {
        let picker = StartEditingPhotoPicker { [weak self] images in
            guard let self else { return }
            self.startEditingPicker = nil
            guard !images.isEmpty else { return }   // cancelled — create nothing
            self.startGridProject(with: images)
        }
        startEditingPicker = picker
        tabBarController.present(picker.makePicker(), animated: true)
    }

    /// Prompts for a custom canvas size (100–4000 px) and starts a freeform collage.
    /// Moved here from the old Home nav bar when "Custom Size" joined the "+" sheet.
    private func promptForCustomCanvas() {
        let alert = UIAlertController(
            title: "Custom Canvas",
            message: "Enter a size in pixels (100–4000).",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "Width"
            field.text = "1080"
            field.keyboardType = .numberPad
            field.accessibilityIdentifier = "freeformWidthField"
        }
        alert.addTextField { field in
            field.placeholder = "Height"
            field.text = "1080"
            field.keyboardType = .numberPad
            field.accessibilityIdentifier = "freeformHeightField"
        }
        alert.addAction(UIAlertAction(title: "Cancel", style: .cancel))
        alert.addAction(UIAlertAction(title: "Create", style: .default) { [weak self, weak alert] _ in
            let width = Double(alert?.textFields?[0].text ?? "") ?? 1080
            let height = Double(alert?.textFields?[1].text ?? "") ?? 1080
            self?.startFreeformProject(size: CGSize(width: width, height: height))
        })
        tabBarController.present(alert, animated: true)
    }

    /// Opens a grid whose template matches the number of photos picked, with each
    /// cell pre-filled in pick order.
    private func startGridProject(with images: [CGImage]) {
        let template = GridTemplate.bestFit(forPhotoCount: images.count)
        let viewModel = GridEditorViewModel(state: GridEditorState(template: template))
        for (index, image) in images.enumerated() where index < template.cellCount {
            viewModel.setImage(image, forCellAt: index)
        }
        attachAutosave(to: viewModel)
        store.save(viewModel)
        pushEditor(with: viewModel)
    }

    // MARK: - Routing

    private func startNewGridProject() {
        let viewModel = GridEditorViewModel()
        attachAutosave(to: viewModel)
        // Persist immediately so the project appears in the gallery on return.
        store.save(viewModel)
        pushEditor(with: viewModel)
    }

    /// Home's "Shapes" quick-start: a blank collage already on a polygon layout, so
    /// the editor opens in Shapes mode rather than needing the segment flipped.
    private func startNewPolygonProject() {
        let state = GridEditorState(layout: .polygon(.diagonalLeft))
        let viewModel = GridEditorViewModel(state: state)
        attachAutosave(to: viewModel)
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

    /// Turns the Carousel tab's chosen `CarouselStartConfig` into frames (via the
    /// slice-3 builders) and pushes the carousel editor. Panoramic first picks a
    /// wide source photo to split.
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
        push(editor)
    }

    private func attachCarouselAutosave(to viewModel: CarouselEditorViewModel) {
        viewModel.onCommit = { [weak self] viewModel in
            self?.store.scheduleSaveCarousel(viewModel)
        }
    }

    /// Starts a video collage (Step 04 slice 5b). A 4:5 canvas with a 2-up stacked
    /// layout is the sensible default for social video; the layout is switchable in
    /// the editor. Persisted immediately so it appears in the gallery on return,
    /// then autosaved on every change (slice 5c).
    private func startVideoCollage() {
        let canvasSize = CanvasSize.size(forAspectRatio: "4:5")
        let viewModel = VideoEditorViewModel(canvasSize: canvasSize, layout: .grid(.twoUpVertical))
        attachVideoAutosave(to: viewModel)
        store.saveVideo(viewModel)
        pushVideoEditor(viewModel)
    }

    private func pushVideoEditor(_ viewModel: VideoEditorViewModel) {
        let editor = VideoEditorViewController(viewModel: viewModel)
        push(editor)
    }

    private func attachVideoAutosave(to viewModel: VideoEditorViewModel) {
        viewModel.onCommit = { [weak self] viewModel in
            self?.store.scheduleSaveVideo(viewModel)
        }
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
        // Routed by record type: video and carousel projects resume into their own
        // editors; everything else is a grid/template/polygon project.
        if let videoVM = store.loadVideoViewModel(id: id) {
            attachVideoAutosave(to: videoVM)
            pushVideoEditor(videoVM)
            return
        }
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
        push(editor)
    }

    /// Every editor hides the tab bar while it is on screen. Without this the bar
    /// would sit under the editor's bottom controls and eat their safe area.
    private func push(_ editor: UIViewController) {
        editor.hidesBottomBarWhenPushed = true
        navigationController.pushViewController(editor, animated: true)
    }

    private func attachAutosave(to viewModel: GridEditorViewModel) {
        viewModel.onCommit = { [weak self] viewModel in
            self?.store.scheduleSave(viewModel)
        }
    }
}
