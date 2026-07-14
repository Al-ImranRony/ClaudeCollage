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

@MainActor
final class AppCoordinator {

    private let navigationController: UINavigationController
    private let store: ProjectStore
    private weak var homeViewController: HomeViewController?

    init(navigationController: UINavigationController, container: ModelContainer) {
        self.navigationController = navigationController
        self.store = ProjectStore(container: container)
    }

    func start() {
        let home = HomeViewController()
        home.summariesProvider = { [weak self] in self?.store.listSummaries() ?? [] }
        home.onNewProject = { [weak self] in self?.startNewGridProject() }
        home.onBrowseTemplates = { [weak self] in self?.showTemplateGallery() }
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

    private func showTemplateGallery() {
        let gallery = TemplateGalleryViewController(service: .shared)
        gallery.onSelectTemplate = { [weak self] template in self?.openTemplate(template) }
        navigationController.pushViewController(gallery, animated: true)
    }

    /// Opens a (free or unlocked) template. Pure photo-grid templates map onto
    /// the Step 01 grid editor; anything richer (text/sticker/art zones, shaped
    /// cells) waits for the template editor of a later 03a slice.
    private func openTemplate(_ template: CollageTemplate) {
        guard let grid = TemplateService.gridTemplate(matching: template) else {
            let alert = UIAlertController(
                title: "Coming Soon",
                message: "This template uses zones the editor doesn't support yet. The template editor arrives in an upcoming update.",
                preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "OK", style: .default))
            navigationController.present(alert, animated: true)
            return
        }

        let state = GridEditorState(
            layout: .grid(grid),
            borderWidth: template.cells.first.map { max($0.borderWidth, 0) } ?? 8,
            background: template.background
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
