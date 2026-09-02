//
//  AppCoordinator.swift
//  Caroullage
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
import WidgetKit

@MainActor
final class AppCoordinator {

    private let tabBarController: AppTabBarController
    private let store: ProjectStore
    /// One library for the whole app: a subject lifted in any editor is offered in
    /// every later one, which is the point of the workflow.
    private let personalStickers: PersonalStickerStore
    private let spotlight = SpotlightIndexer()
    private let aiService = AIService()
    private let recentPhotos = RecentPhotoProvider()
    private let widgetSnapshots = WidgetSnapshotStore()
    /// Retains the panoramic PHPicker delegate for the life of the pick.
    private var panoramicPicker: PanoramicSourcePicker?
    /// Retains the "+" flow's photo picker delegate for the life of the pick.
    private var startEditingPicker: StartEditingPhotoPicker?
    /// Home, kept so onboarding's answer can reorder what it leads with.
    private weak var homeViewController: HomeViewController?

    init(tabBarController: AppTabBarController, container: ModelContainer) {
        self.tabBarController = tabBarController
        self.store = ProjectStore(container: container)
        self.personalStickers = PersonalStickerStore(container: container)
    }

    func start() {
        let home = HomeViewController()
        homeViewController = home
        home.featuredTemplatesProvider = { TemplateService.shared.templates }
        home.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }
        home.onBrowseTemplates = { [weak self] in self?.selectTemplatesTab() }
        // The bundled carousel catalog, unfiltered: Home is the showcase, so Home
        // is where the "only what the sample-content manifest dresses" rule lives —
        // one rule, in one place, for all three strips.
        home.carouselTemplatesProvider = { TemplateService.shared.carouselTemplates }
        home.onSelectCarouselTemplate = { [weak self] template in
            self?.openCarouselTemplate(template)
        }
        home.videoShowcasesProvider = { SampleContentCatalog.shared.videoShowcases }
        home.onSelectVideoShowcase = { [weak self] showcase in
            self?.openVideoShowcase(showcase)
        }
        // "See All" finally means see all: the Carousel tab is the gallery now.
        home.onBrowseCarousels = { [weak self] in self?.selectCarouselTab() }
        home.onNewProject = { [weak self] in self?.startNewGridProject() }
        home.onNewPolygon = { [weak self] in self?.startNewPolygonProject() }
        home.onNewVideoCollage = { [weak self] in self?.startVideoCollage() }
        home.onNewCarousel = { [weak self] in self?.presentCarouselTypePicker() }
        home.photoAccessProvider = { [weak self] in self?.recentPhotos.access ?? .denied }
        home.requestPhotoAccess = { [weak self] in
            await self?.recentPhotos.requestAccess() ?? .denied
        }
        home.suggestedLayoutsProvider = { [weak self] in
            guard let self else { return [] }
            let photos = await self.recentPhotos.recentPhotos()
            // Below three photos there is nothing meaningful to suggest — a single
            // photo has exactly one sensible layout.
            guard photos.count >= 3 else { return [] }
            return await self.aiService.suggestLayouts(for: photos, limit: 5)
        }
        home.onSelectSuggestedLayout = { [weak self] template in
            self?.startProjectFromRecentPhotos(template: template)
        }

        let templates = TemplateGalleryViewController(service: .shared)
        templates.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }

        let projects = makeGallery(configuration: .allProjects) { [weak self] in
            self?.startNewGridProject()
        }
        // The Carousel tab has been three things. It was the type picker (a
        // wizard as a tab root). Step 06 made it the carousels you had MADE,
        // which turned out to be the Projects grid with a filter — every card
        // already one tab over, and Projects' "By type" sort already groups
        // them. It is now the twenty bundled carousel TEMPLATES, which is the
        // one thing no other surface was showing.
        let carousels = CarouselGalleryViewController(service: .shared)
        carousels.onSelectTemplate = { [weak self] template in
            self?.openCarouselTemplate(template)
        }

        tabBarController.setTabs([
            // Home is the one tab a user returns to rather than visits, so it
            // gets the outline-to-filled treatment: a plain house that fills in
            // when you are there. The rest stay filled — one moving part, not four.
            (home, tabItem("Home", "house", selected: "house.fill", "homeTab")),
            (templates, tabItem("Templates", "rectangle.3.group.fill", "templatesButton")),
            // Carousel sits mid-bar, where the thumb lands, because it is the
            // app's signature format. Projects is the archive you visit least, so
            // it takes the edge.
            (carousels, tabItem("Carousel", "rectangle.stack.fill", "carouselButton")),
            (projects, tabItem("Projects", "square.grid.2x2.fill", "projectsTab")),
        ])
        tabBarController.onStartEditing = { [weak self] in self?.presentStartEditingSheet() }

        // Bundled templates back the Home strips; the gallery loads them too, but
        // Home is shown first so it cannot wait for that.
        //
        // The carousel catalog had never been loaded ANYWHERE — twenty bundled
        // templates that no screen had ever surfaced. Home's Carousels strip is
        // the first thing to ask for them.
        _ = TemplateService.shared.loadBundledTemplates()
        _ = TemplateService.shared.loadBundledCarouselTemplates()
        home.reload()

        IntentRouter.shared.onRequest = { [weak self] request in self?.handle(request) }
        refreshPlatformSurfaces()

        // Reconcile the entitlement with the App Store, load the paywall's
        // products, and start listening for renewals. Off the launch path: the
        // cached tier already gates the UI correctly while this settles.
        Task { await PurchaseService.shared.start() }

        // Presented once the shell is on screen — see `onFirstAppearance`.
        tabBarController.onFirstAppearance = { [weak self] in
            self?.presentOnboardingIfFirstLaunch()
        }
    }

    // MARK: - Onboarding (Step 06 phase 6.3)

    /// First launch only. The funnel ends on the paywall, and however that ends
    /// the app drops into Home on the free tier — no relaunch, and no second run.
    private func presentOnboardingIfFirstLaunch() {
        guard OnboardingViewModel.shouldPresent() else { return }

        let onboarding = OnboardingHostingController.make(
            requestPhotoAccess: { [weak self] in
                await self?.recentPhotos.requestAccess() ?? .denied
            }
        )
        onboarding.recentPhotosProvider = { [weak self] in
            await self?.recentPhotos.recentPhotos(limit: 4) ?? []
        }
        onboarding.onFinished = { [weak self] in
            // What they said they make decides which template Home leads with.
            self?.applyOnboardingPreference()
        }
        tabBarController.present(onboarding, animated: false)
    }

    /// Puts the templates matching the user's stated interest first on Home.
    private func applyOnboardingPreference() {
        guard let kind = OnboardingViewModel.storedCreatorKind() else { return }
        let preferred: String? = switch kind {
        case .carousels: "Story"
        case .reels: "Story"
        case .pinterest: "Grid"
        case .fun: nil
        }
        guard let preferred, let home = homeViewController else { return }
        let all = TemplateService.shared.templates
        let matching = all.filter { $0.category.caseInsensitiveCompare(preferred) == .orderedSame }
        guard !matching.isEmpty else { return }
        home.featuredTemplatesProvider = { matching + all.filter { !matching.contains($0) } }
        home.reload()
    }

    // MARK: - Platform surfaces (Step 05 batch C)

    /// Republishes what lives outside the app: the widget snapshot and the
    /// Spotlight index.
    ///
    /// Called after anything that changes the project list. Both are best-effort —
    /// neither may ever interfere with saving, so failures are swallowed rather
    /// than surfaced.
    private func refreshPlatformSurfaces() {
        let summaries = store.listSummaries()
        spotlight.index(summaries)
        widgetSnapshots.write(WidgetSnapshot(
            projects: summaries.map {
                WidgetProjectEntry(
                    id: $0.id, updatedAt: $0.updatedAt,
                    thumbnailData: $0.thumbnail?.jpegData(compressionQuality: 0.7))
            },
            generatedAt: Date()
        ))
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// Runs an intent's request through the same routing the UI uses, so Siri and
    /// the app can never diverge on what "new carousel" means.
    private func handle(_ request: IntentRouter.Request) {
        switch request {
        case .newGridCollage:
            // The photo count is honoured once the picker returns; the intent
            // deliberately does not reach into PhotoKit itself.
            startNewGridProject()
        case let .newStoryCarousel(frameCount):
            beginCarousel(config: CarouselStartConfig(
                type: .matched, frameCount: frameCount, aspectRatio: "4:5"))
        case .exportLastProject:
            guard let latest = store.listSummaries().first else { return }
            openProject(id: latest.id)
        }
    }

    private func tabItem(
        _ title: String, _ symbol: String, selected: String? = nil, _ identifier: String
    ) -> TabDescriptor {
        TabDescriptor(title: title, symbol: symbol, selectedSymbol: selected, identifier: identifier)
    }

    // MARK: - Galleries

    /// Builds the saved-project gallery.
    ///
    /// This ran twice until Step 07 — the Projects tab and a carousels-only
    /// Carousel tab — which is why the configuration is a parameter rather than
    /// baked in. That second caller is gone (the Carousel tab is the template
    /// catalog now, and Projects' "By type" sort already groups carousels), so
    /// today there is exactly one. The seam stays: `Configuration` is still the
    /// honest way to describe a gallery, and collapsing it would only have to be
    /// undone the next time a second one appears.
    private func makeGallery(
        configuration: ProjectsViewController.Configuration,
        onNew: @escaping () -> Void
    ) -> ProjectsViewController {
        let gallery = ProjectsViewController(configuration: configuration)
        gallery.summariesProvider = { [weak self] in self?.store.listSummaries() ?? [] }
        gallery.onNewProject = onNew
        gallery.onOpenProject = { [weak self] id in self?.openProject(id: id) }
        gallery.onRenameProject = { [weak self] id, name in
            self?.store.rename(id: id, to: name)
            self?.refreshPlatformSurfaces()
        }
        gallery.onDuplicateProject = { [weak self] id in
            self?.store.duplicate(id: id)
            self?.refreshPlatformSurfaces()
        }
        // Export routes through opening the project: the export sheet lives in the
        // editor and knows how to render that project's kind. Re-implementing it
        // here would be a second export path to keep in sync.
        gallery.onExportProject = { [weak self] id in self?.openProject(id: id) }
        gallery.onDeleteProject = { [weak self] id in
            self?.store.delete(id: id)
            self?.spotlight.remove(id: id)
            self?.refreshPlatformSurfaces()
        }
        return gallery
    }

    /// The carousel type picker, as a sheet over whichever tab you are on.
    ///
    /// Two doors reach it — the "+" menu's Carousel row and the Carousel tab's
    /// "New" bar button. (Until Step 07 the second door was that tab's empty
    /// state, which went with the saved-carousel gallery it belonged to.) The
    /// `NewStoryCarousel` intent is a third entry to carousels but skips the
    /// picker: it already knows the type and frame count.
    private func presentCarouselTypePicker() {
        let picker = CarouselStartViewController()
        picker.onCreate = { [weak self] config in self?.beginCarousel(config: config) }
        tabBarController.present(picker, animated: true)
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

    private func selectCarouselTab() {
        tabBarController.selectTab { $0 is CarouselGalleryViewController }
    }

    // MARK: - "Start Editing" (+)

    /// The floating "+" — the one place creation-with-a-choice begins.
    ///
    /// Grid vs Shapes vs Freeform is deliberately NOT asked here: pick photos and
    /// start editing, then swap layout from the editor's own Layout/Shape pickers.
    private func presentStartEditingSheet() {
        let sheet = StartEditingSheetViewController(
            onCamera: { [weak self] in self?.presentCamera() },
            onImage: { [weak self] in self?.pickPhotosForNewCollage() },
            onVideo: { [weak self] in self?.startVideoCollage() },
            onCarousel: { [weak self] in self?.presentCarouselTypePicker() },
            onCustomCanvas: { [weak self] in self?.promptForCustomCanvas() }
        )
        tabBarController.present(sheet, animated: true)
    }

    /// Shoot a photo and go straight into a collage with it — the same landing
    /// as picking one from the library, so the two entries converge immediately.
    private func presentCamera() {
        let camera = CameraCaptureViewController()
        camera.modalPresentationStyle = .fullScreen
        camera.onCapture = { [weak self] image in
            self?.startGridProject(with: [image])
        }
        // No camera on this device: the screen offers the library instead of
        // dead-ending, and that choice lands back in the normal photo flow.
        camera.onChooseFromLibrary = { [weak self] in
            self?.pickPhotosForNewCollage()
        }
        tabBarController.present(camera, animated: true)
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
        Task { @MainActor in
            // AI auto-layout: score every grid against where the faces and salient
            // regions actually are, and fall back to a count-based fit if analysis
            // yields nothing (which is every simulator run — Vision needs a device).
            let suggested = await aiService.suggestLayouts(for: images, limit: 1).first
            self.openGridProject(with: images,
                                 template: suggested ?? .bestFit(forPhotoCount: images.count))
        }
    }

    /// Builds a collage from the user's recent photos using a suggested layout —
    /// the payoff for the Suggested Layouts row.
    private func startProjectFromRecentPhotos(template: GridTemplate) {
        Task { @MainActor in
            let photos = await self.recentPhotos.recentPhotos(limit: template.cellCount)
            guard !photos.isEmpty else { return }
            self.openGridProject(with: photos, template: template)
        }
    }

    private func openGridProject(with images: [CGImage], template: GridTemplate) {
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
            presentCarouselEditor(frames: frames, images: [:], canvasSize: canvasSize,
                                  type: config.type, axis: config.splitAxis)
        case .gridPreview:
            // v1 seeds a default 4-up grid; picking an existing grid project as the
            // source is a follow-up. Frame count derives from the grid.
            let grid = GridEditorState(template: .fourSquare)
            let frames = service.buildGridPreviewCarousel(from: grid, aspectRatio: config.aspectRatio)
            presentCarouselEditor(frames: frames, images: [:], canvasSize: canvasSize,
                                  type: .gridPreview, axis: config.splitAxis)
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
                frames: build.frames, images: build.images, canvasSize: canvasSize,
                type: .panoramic, axis: config.splitAxis)
        }
        panoramicPicker = picker
        navigationController.present(picker.makePicker(), animated: true)
    }

    private func presentCarouselEditor(
        frames: [CarouselFrame], images: [UUID: CGImage], canvasSize: CGSize,
        type: CarouselType, axis: SplitAxis
    ) {
        let viewModel = CarouselEditorViewModel(
            frames: frames, images: images, canvasSize: canvasSize, carouselType: type, axis: axis)
        attachCarouselAutosave(to: viewModel)
        store.saveCarousel(viewModel)   // persist immediately so it lands on Home
        presentCarouselEditor(viewModel: viewModel)
    }

    private func presentCarouselEditor(viewModel: CarouselEditorViewModel) {
        let editor = CarouselEditorViewController(viewModel: viewModel)
        editor.onEditFrame = { [weak self] frameVM in self?.pushEditor(with: frameVM) }
        // The axis is presentation, but it is the user's choice, so it persists
        // with the project rather than resetting on the next open.
        editor.onAxisChanged = { [weak self] _ in self?.store.scheduleSaveCarousel(viewModel) }
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

    /// Opens a bundled carousel template from the Home showcase.
    ///
    /// The same deal `openTemplate` offers: the template's frames with the photo
    /// zones EMPTY and its text prefilled, so the user rebuilds the preview they
    /// tapped with their own photos. The sample photography sells the structure;
    /// it never lands in the project.
    private func openCarouselTemplate(_ template: CarouselTemplate) {
        // The lock badge on the card is cosmetic; this is the gate. Routed here
        // rather than in each caller so Home, the Carousel gallery and any
        // future door give the same answer.
        guard TemplateService.shared.canOpen(template) else {
            Haptics.boundary()
            tabBarController.presentPaywall { [weak self] in
                self?.openCarouselTemplate(template)
            }
            return
        }

        let frames = CarouselService().buildCarousel(from: template)
        // A template that parses to no frames has nothing to open — bail rather
        // than pushing an empty editor.
        guard !frames.isEmpty else { return }
        presentCarouselEditor(
            frames: frames,
            images: [:],
            canvasSize: CanvasSize.size(forAspectRatio: template.canvasAspectRatio),
            type: template.carouselType,
            // Horizontal is the carousel editor's default reading axis; the user
            // can flip it in the editor, and that choice then persists.
            axis: .horizontal)
    }

    /// Opens the video editor preset to a Home showcase's layout, cells empty —
    /// the moving equivalent of `openTemplate`.
    private func openVideoShowcase(_ showcase: SampleContentManifest.VideoShowcase) {
        // The manifest carries the layout as a `GridTemplate` raw value. An
        // unknown one means the manifest and the enum have drifted; do nothing
        // rather than open a layout the loop was not composed in.
        guard let grid = GridTemplate(rawValue: showcase.layout) else { return }
        let viewModel = VideoEditorViewModel(
            canvasSize: CanvasSize.size(forAspectRatio: "4:5"), layout: .grid(grid))
        attachVideoAutosave(to: viewModel)
        store.saveVideo(viewModel)
        pushVideoEditor(viewModel)
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
        // Resolved here rather than inside the view model so it never touches
        // SwiftData directly, and so the editor stays constructible in tests.
        viewModel.personalStickerImages = { [weak self] overlays in
            self?.personalStickers.images(for: overlays) ?? [:]
        }
        let editor = GridEditorViewController(viewModel: viewModel)
        editor.personalStickers = personalStickers
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
