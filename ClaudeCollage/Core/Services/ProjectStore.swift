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

import AVFoundation
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

    // MARK: - Video save / load (Step 04)

    /// Debounced video-collage save (mirrors `scheduleSave`).
    func scheduleSaveVideo(_ viewModel: VideoEditorViewModel) {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in self?.saveVideo(viewModel) }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4, execute: work)
    }

    /// Persists a video collage: copies every referenced clip (and the music track)
    /// into the project folder, encodes the cell/music state, and upserts the record.
    ///
    /// Copying rather than storing a Photos identifier is deliberate: a picked clip
    /// is backed either by the Photos library or by a temp-dir copy from
    /// `VideoSourcePicker`, and both can disappear — the copy makes resume
    /// self-contained. The cost is duplicated storage for large clips; referencing
    /// the original `PHAsset` where it's still available is a possible refinement.
    func saveVideo(_ viewModel: VideoEditorViewModel) {
        pendingSave?.cancel()
        pendingSave = nil

        let projectID = viewModel.projectID
        let data = viewModel.projectData()

        writeMedia(viewModel.mediaFileURLs(), forProject: projectID,
                   referenced: data.referencedMediaIDs)

        let payload = try? JSONEncoder().encode(data)
        let thumbnailData = viewModel.thumbnail.flatMap {
            UIImage(cgImage: $0).jpegData(compressionQuality: 0.8)
        }

        let project = fetchProject(id: projectID) ?? {
            let new = CollageProject(mode: .video, canvasSize: viewModel.canvasSize)
            new.id = projectID
            context.insert(new)
            return new
        }()

        project.mode = .video
        project.templateID = data.layout.persistID
        project.frameCount = data.cells.count
        project.canvasSize = viewModel.canvasSize
        project.videoData = payload
        // Keep an earlier thumbnail if this save happened before one was rendered.
        if let thumbnailData { project.previewThumbnail = thumbnailData }
        project.updatedAt = Date()

        try? context.save()
    }

    /// Rehydrates a saved video collage: decodes the cell/music state and reopens
    /// the copied clips from disk.
    func loadVideoViewModel(id: UUID) -> VideoEditorViewModel? {
        guard let project = fetchProject(id: id), project.mode == .video,
              let data = project.videoData,
              let payload = try? JSONDecoder().decode(VideoProjectData.self, from: data) else {
            return nil
        }
        let media = loadMedia(forProject: id, referenced: payload.referencedMediaIDs)
        let viewModel = VideoEditorViewModel(
            canvasSize: project.canvasSize, layout: payload.layout,
            borderWidth: CGFloat(payload.borderWidth), projectID: project.id)
        viewModel.restore(
            data: payload,
            assets: media,
            musicAsset: payload.music?.musicID.flatMap { media[$0] })
        return viewModel
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

    // MARK: - Private: video/audio disk cache

    /// Copies each referenced clip into the project folder as `<mediaID>.<ext>`.
    /// Ids are stable, so an already-copied clip is left alone; a source that IS
    /// the destination (re-saving a restored project) is skipped.
    private func writeMedia(
        _ urls: [UUID: URL],
        forProject projectID: UUID,
        referenced: Set<UUID>
    ) {
        let directory = mediaDirectory(projectID)
        try? fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        for id in referenced {
            guard let source = urls[id], existingMediaURL(id, in: directory) == nil else { continue }
            let ext = source.pathExtension.isEmpty ? "mov" : source.pathExtension
            let destination = directory.appendingPathComponent("\(id.uuidString).\(ext)")
            guard source.standardizedFileURL != destination.standardizedFileURL else { continue }
            try? fileManager.copyItem(at: source, to: destination)
        }
    }

    private func loadMedia(
        forProject projectID: UUID,
        referenced: Set<UUID>
    ) -> [UUID: AVAsset] {
        let directory = mediaDirectory(projectID)
        var result: [UUID: AVAsset] = [:]
        for id in referenced {
            if let url = existingMediaURL(id, in: directory) {
                result[id] = AVURLAsset(url: url)
            }
        }
        return result
    }

    /// The copied file for a media id, whatever extension it was saved with.
    private func existingMediaURL(_ id: UUID, in directory: URL) -> URL? {
        let contents = (try? fileManager.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil)) ?? []
        return contents.first { $0.deletingPathExtension().lastPathComponent == id.uuidString }
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

    /// Copied video clips + the music track for a video project. Lives under the
    /// project directory, so `delete(id:)` reclaims it along with everything else.
    private func mediaDirectory(_ id: UUID) -> URL {
        projectDirectory(id).appendingPathComponent("media", isDirectory: true)
    }
}
