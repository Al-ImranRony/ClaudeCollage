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

    private let completion: (AVAsset?) -> Void
    /// Fired (main actor) when the picked clip has to be transcoded before it can
    /// be used — see `normalized(_:)`. The host shows progress; it can take a few
    /// seconds for a long slo-mo clip.
    private let willTranscode: (() -> Void)?

    init(willTranscode: (() -> Void)? = nil, completion: @escaping (AVAsset?) -> Void) {
        self.willTranscode = willTranscode
        self.completion = completion
    }

    /// A single-video PHPicker wired to this object.
    func makePicker() -> PHPickerViewController {
        // `photoLibrary:` is what makes `assetIdentifier` available for route 1.
        var config = PHPickerConfiguration(photoLibrary: .shared())
        config.filter = .videos
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        return picker
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let result = results.first else {
            completion(nil)
            return
        }

        if let identifier = result.assetIdentifier,
           let phAsset = PHAsset.fetchAssets(withLocalIdentifiers: [identifier], options: nil).firstObject {
            loadViaPhotoKit(phAsset)
        } else {
            loadViaFileCopy(result.itemProvider)
        }
    }

    // MARK: - Route 1 — PHAsset via PHImageManager (no copy, iCloud-aware)

    private func loadViaPhotoKit(_ phAsset: PHAsset) {
        Task { @MainActor in
            do {
                let asset = try await VideoAssetLoader().loadAsset(for: phAsset)
                completion(try await normalized(asset))
            } catch {
                completion(nil)
            }
        }
    }

    /// Guarantees the returned asset is **file-backed**.
    ///
    /// Photos returns slo-mo (and other adjusted) videos as an `AVComposition`,
    /// which has no URL — nothing for `ProjectStore` to copy into the project, so
    /// the cell would resume empty. Those get archived to a real file first, which
    /// bakes in the slow-motion timing and keeps the rest of the pipeline unaware
    /// that this case exists. Ordinary clips pass straight through untouched.
    private func normalized(_ asset: AVAsset) async throws -> AVAsset {
        if asset is AVURLAsset { return asset }
        willTranscode?()
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

    private func loadViaFileCopy(_ provider: NSItemProvider) {
        let destination = FileManager.default.temporaryDirectory
            .appendingPathComponent("VideoCell-\(UUID().uuidString).mov")
        // @Sendable closure: captures only Sendable values (the destination URL) and
        // hops back to main before touching `completion`.
        provider.loadFileRepresentation(forTypeIdentifier: UTType.movie.identifier) { [weak self] url, _ in
            var copied: URL?
            if let url {
                // The provided URL is deleted as soon as this closure returns, so the
                // copy has to happen here, synchronously.
                try? FileManager.default.copyItem(at: url, to: destination)
                copied = destination
            }
            let final = copied
            DispatchQueue.main.async {
                guard let self else { return }
                guard let final, FileManager.default.fileExists(atPath: final.path) else {
                    self.completion(nil)
                    return
                }
                self.completion(AVURLAsset(url: final))
            }
        }
    }
}
