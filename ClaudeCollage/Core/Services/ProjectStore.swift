//
//  ProjectStore.swift
//  ClaudeCollage
//
//  Step 01 — persistence for grid projects.
//
//  SwiftData holds the project record (id, timestamps, gallery thumbnail, and
//  the serialized editor state). The photos themselves are written as JPEGs to
//  a per-project folder on disk and referenced by stable image ids, so the
//  database stays small.
//

import Foundation
import SwiftData
import UIKit

/// Lightweight row for the home gallery.
struct ProjectSummary: Identifiable, Sendable {
    let id: UUID
    let updatedAt: Date
    let thumbnail: UIImage?
    let mode: CollageMode
}

@MainActor
final class ProjectStore {

    // Retain the container for the store's lifetime. If only `mainContext` were
    // held, the container could deallocate and disconnect its SQLite store,
    // trapping the next fetch.
    private let container: ModelContainer
    private var context: ModelContext { container.mainContext }
    private let fileManager = FileManager.default

    init(container: ModelContainer) {
        self.container = container
    }

    // MARK: - Listing

    func listSummaries() -> [ProjectSummary] {
        let projects = ((try? context.fetch(FetchDescriptor<CollageProject>())) ?? [])
            .sorted { $0.updatedAt > $1.updatedAt }
        return projects.map { project in
            ProjectSummary(
                id: project.id,
                updatedAt: project.updatedAt,
                thumbnail: project.previewThumbnail.flatMap(UIImage.init(data:)),
                mode: project.mode
            )
        }
    }

    // MARK: - Save

    private var pendingSave: DispatchWorkItem?

    /// Coalesces rapid commits into a single disk write ~0.4s later, keeping the
    /// thumbnail render + SwiftData save off the interaction hot path. The view
    /// model is captured strongly so a save still lands if the editor is popped.
    func scheduleSave(_ viewModel: GridEditorViewModel) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.save(viewModel)
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Persists the view model: writes any new images to disk, encodes the
    /// editor state + a gallery thumbnail, and upserts the SwiftData record.
    func save(_ viewModel: GridEditorViewModel) {
        pendingSave?.cancel()
        pendingSave = nil

        let projectID = viewModel.projectID
        let state = viewModel.state

        writeImages(viewModel.sourceImageSnapshot(), forProject: projectID,
                    referenced: referencedImageIDs(in: state))

        let stateData = try? JSONEncoder().encode(state)
        let thumbnailData = makeThumbnailData(from: viewModel)

        let project = fetchProject(id: projectID) ?? {
            let new = CollageProject(mode: .grid, canvasSize: viewModel.canvasSize)
            new.id = projectID
            context.insert(new)
            return new
        }()

        project.mode = state.layout.isPolygon ? .polygon : .grid
        project.templateID = state.layout.persistID
        project.canvasSize = viewModel.canvasSize
        project.gridStateData = stateData
        project.previewThumbnail = thumbnailData
        project.updatedAt = Date()

        try? context.save()
    }

    // MARK: - Load

    /// Rehydrates a saved project into a view model (state + decoded images).
    func loadViewModel(id: UUID) -> GridEditorViewModel? {
        guard let project = fetchProject(id: id),
              let data = project.gridStateData,
              let state = try? JSONDecoder().decode(GridEditorState.self, from: data) else {
            return nil
        }

        let viewModel = GridEditorViewModel(
            projectID: project.id,
            canvasSize: project.canvasSize,
            state: state
        )
        let images = loadImages(forProject: project.id, referenced: referencedImageIDs(in: state))
        viewModel.restore(state: state, images: images)
        return viewModel
    }

    // MARK: - Carousel save / load (Step 03b)

    /// Debounced carousel save (mirrors `scheduleSave`).
    func scheduleSaveCarousel(_ viewModel: CarouselEditorViewModel) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveCarousel(viewModel) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Persists a carousel: writes every frame's referenced photos to disk, encodes
    /// the frame array + a frame-0 gallery thumbnail, and upserts the record.
    func saveCarousel(_ viewModel: CarouselEditorViewModel) {
        pendingSave?.cancel()
        pendingSave = nil

        let projectID = viewModel.projectID
        let frames = viewModel.frames
        writeImages(viewModel.imagesSnapshot(), forProject: projectID,
                    referenced: referencedImageIDs(in: frames))

        let framesData = try? JSONEncoder().encode(frames)
        let thumbnailData = carouselThumbnailData(viewModel)

        let project = fetchProject(id: projectID) ?? {
            let new = CollageProject(mode: .carousel, canvasSize: viewModel.canvasSize)
            new.id = projectID
            context.insert(new)
            return new
        }()

        project.mode = .carousel
        project.carouselType = viewModel.carouselType
        project.frameCount = frames.count
        project.canvasSize = viewModel.canvasSize
        project.carouselData = framesData
        project.previewThumbnail = thumbnailData
        project.updatedAt = Date()

        try? context.save()
    }

    /// Rehydrates a saved carousel into a view model (frames + decoded images).
    func loadCarouselViewModel(id: UUID) -> CarouselEditorViewModel? {
        guard let project = fetchProject(id: id), project.mode == .carousel,
              let data = project.carouselData,
              let frames = try? JSONDecoder().decode([CarouselFrame].self, from: data) else {
            return nil
        }
        let images = loadImages(forProject: id, referenced: referencedImageIDs(in: frames))
        return CarouselEditorViewModel(
            frames: frames, images: images, canvasSize: project.canvasSize,
            carouselType: project.carouselType ?? .matched, projectID: project.id)
    }

    private func carouselThumbnailData(_ viewModel: CarouselEditorViewModel) -> Data? {
        guard let first = viewModel.frames.first else { return nil }
        let vm = GridEditorViewModel(canvasSize: viewModel.canvasSize, state: first.state)
        vm.restore(state: first.state, images: viewModel.imagesSnapshot())
        guard let cgImage = vm.renderThumbnail(maxDimension: 320) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    // MARK: - Delete

    func delete(id: UUID) {
        if let project = fetchProject(id: id) {
            context.delete(project)
            try? context.save()
        }
        try? fileManager.removeItem(at: projectDirectory(id))
    }

    // MARK: - Private: SwiftData

    private func fetchProject(id: UUID) -> CollageProject? {
        let predicate = #Predicate<CollageProject> { $0.id == id }
        var descriptor = FetchDescriptor<CollageProject>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try? context.fetch(descriptor).first
    }

    // MARK: - Private: image disk cache

    private func writeImages(
        _ images: [UUID: CGImage],
        forProject projectID: UUID,
        referenced: Set<UUID>
    ) {
        let directory = imagesDirectory(projectID)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for id in referenced {
            let url = directory.appendingPathComponent("\(id.uuidString).jpg")
            guard !fileManager.fileExists(atPath: url.path), let cgImage = images[id] else { continue }
            if let data = UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.95) {
                try? data.write(to: url, options: .atomic)
            }
        }
    }

    private func loadImages(
        forProject projectID: UUID,
        referenced: Set<UUID>
    ) -> [UUID: CGImage] {
        let directory = imagesDirectory(projectID)
        var result: [UUID: CGImage] = [:]
        for id in referenced {
            let url = directory.appendingPathComponent("\(id.uuidString).jpg")
            // Decode straight to the display cap — never materialize full-res.
            if let cgImage = ImageDownsampler.downsample(url: url) {
                result[id] = cgImage
            }
        }
        return result
    }

    private func referencedImageIDs(in state: GridEditorState) -> Set<UUID> {
        Set(state.cells.compactMap { $0.imageID })
    }

    private func referencedImageIDs(in frames: [CarouselFrame]) -> Set<UUID> {
        Set(frames.flatMap { $0.state.cells.compactMap { $0.imageID } })
    }

    private func makeThumbnailData(from viewModel: GridEditorViewModel) -> Data? {
        guard let cgImage = viewModel.renderThumbnail(maxDimension: 320) else { return nil }
        return UIImage(cgImage: cgImage).jpegData(compressionQuality: 0.8)
    }

    // MARK: - Private: paths

    private func projectsRoot() -> URL {
        let docs = fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return docs.appendingPathComponent("Projects", isDirectory: true)
    }

    private func projectDirectory(_ id: UUID) -> URL {
        projectsRoot().appendingPathComponent(id.uuidString, isDirectory: true)
    }

    private func imagesDirectory(_ id: UUID) -> URL {
        projectDirectory(id).appendingPathComponent("images", isDirectory: true)
    }
}
