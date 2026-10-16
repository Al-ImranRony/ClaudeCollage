//
//  VideoSourcePicker.swift
//  Caroullage
//
//  Step 04 slice 5b — picks the clip for a video cell. A small NSObject wrapper
//  around PHPicker filtered to `.videos`, mirroring `PanoramicSourcePicker`.
//
//  Two resolution routes, in order:
//  1. The plan's route — the picker result's `assetIdentifier` → `PHAsset` →
//     `VideoAssetLoader` (`PHImageManager.requestAVAsset`), which streams the
//     ORIGINAL asset (and downloads it from iCloud when needed) with no copy.
//  2. Fallback — `loadFileRepresentation` copies the movie into our temp dir and we
//     open it as an `AVURLAsset`. This is what runs when the photo library is not
//     authorized for reading: PHPicker itself is out-of-process and still works, but
//     the PHAsset fetch would come back empty.
//
//  System picker UI ⇒ verified by on-device manual QA, not a headless test.
//

import AVFoundation
import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class VideoSourcePicker: NSObject, PHPickerViewControllerDelegate {

    private let completion: ([AVAsset]) -> Void
    /// Fired (main actor) when the picked clip has to be transcoded before it can
    /// be used — see `normalized(_:)`. The host shows progress; it can take a few
    /// seconds for a long slo-mo clip.
    private let willTranscode: (() -> Void)?
    private let selectionLimit: Int
    private var didAnnounceTranscode = false

    /// One clip, for one slot.
    convenience init(willTranscode: (() -> Void)? = nil, completion: @escaping (AVAsset?) -> Void) {
        self.init(selectionLimit: 1, willTranscode: willTranscode) { completion($0.first) }
    }

    /// Up to `selectionLimit` clips, delivered in the order the user picked them
    /// (the picker numbers its selection) — how "Add clips" fills a template's
    /// empty slots in one trip. A clip that fails to load is skipped rather than
    /// failing the batch.
    init(selectionLimit: Int, willTranscode: (() -> Void)? = nil,
         completion: @escaping ([AVAsset]) -> Void) {
        self.selectionLimit = max(1, selectionLimit)
        self.willTranscode = willTranscode
        self.completion = completion
    }

    /// A PHPicker filtered to videos, wired to this object.
    func makePicker() -> PHPickerViewController {
        // `photoLibrary:` is what makes `assetIdentifier` available for route 1.
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = selectionLimit
        if selectionLimit > 1 { config.selection = .ordered }
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        return picker
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            completion([])
            return
        }
        Task { @MainActor in
            var assets: [AVAsset] = []
            // One at a time, in pick order: the order IS which slot each fills.
            for result in results {
                if let asset = await load(result) { assets.append(asset) }
            }
            completion(assets)
        }
    }

    @MainActor
    private func load(_ result: PHPickerResult) async -> AVAsset? {
        if let identifier = result.assetIdentifier,
           let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
            return await loadViaPhotoKit(phAsset)
        }
        guard let url = await Self.copyFile(from: result.itemProvider) else { return nil }
        return AVURLAsset(url: url)
    }

    // MARK: - Route 1 — PHAsset via PHImageManager (no copy, iCloud-aware)

    @MainActor
    private func loadViaPhotoKit(_ phAsset: PHAsset) async -> AVAsset? {
        do {
            let asset = try await VideoAssetLoader().loadAsset(for: phAsset)
            return try await normalized(asset)
        } catch {
            return nil
        }
    }

    /// Guarantees the returned asset is **file-backed**.
    ///
    /// Photos returns slo-mo (and other adjusted) videos as an `AVComposition`,
    /// which has no URL — nothing for `ProjectStore` to copy into the project, so
    /// the cell would resume empty. Those get archived to a real file first, which
    /// bakes in the slow-motion timing and keeps the rest of the pipeline unaware
    /// that this case exists. Ordinary clips pass straight through untouched.
    @MainActor
    private func normalized(_ asset: AVAsset) async throws -> AVAsset {
        if asset is AVURLAsset { return asset }
        // Once per batch: the host's progress modal covers every clip after it.
        if !didAnnounceTranscode {
            didAnnounceTranscode = true
            willTranscode?()
        }
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoCell-\(UUID().uuidString).mp4")
        try await Self.archive(AssetBox(asset), to: destination)
        return AVURLAsset(url: destination)
    }

    /// Carries the non-Sendable `AVAsset` out to the nonisolated composer (the same
    /// idiom as `VideoAssetLoader.SendableBox`); it is only read there.
    private struct AssetBox: @unchecked Sendable {
        let asset: AVAsset
        init(_ asset: AVAsset) { self.asset = asset }
    }

    private static func archive(_ box: AssetBox, to url: URL) async throws {
        try await VideoComposer().archive(asset: box.asset, to: url)
    }

    // MARK: - Route 2 — copy the file out of the picker sandbox

    /// The movie copied into our temp dir, or nil. Only the URL crosses back —
    /// the asset is opened on the caller's actor.
    private static func copyFile(from provider: NSItemProvider) async -> URL? {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoCell-\(UUID().uuidString).mov")
        return await withCheckedContinuation { (continuation: CheckedContinuation<URL?, Never>) in
            // Explicitly @Sendable: PhotoKit calls this off the main thread, and a
            // closure inferred @MainActor would trap there (see the project note
            // on the Swift 6 DispatchWorkItem trap).
            provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { @Sendable url, _ in
                guard let url else {
                    continuation.resume(returning: nil)
                    return
                }
                // The provided URL is deleted as soon as this closure returns, so
                // the copy has to happen here, synchronously.
                try? FileManager.default.copyItem(at: url, to: destination)
                let exists = FileManager.default.fileExists(atPath: destination.path)
                continuation.resume(returning: exists ? destination : nil)
            }
        }
    }
}
