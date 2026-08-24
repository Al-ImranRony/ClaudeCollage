//
//  PhotoLibrarySaver.swift
//  Caroullage
//
//  Step 04 slice 2 — one place to save exported media (image data or a video file)
//  to the Photos library, used by every editor's Universal Export sheet.
//
//  PhotoKit invokes its authorization / performChanges completion handlers on a
//  BACKGROUND queue. Under Swift 6 complete concurrency a non-Sendable closure
//  inside a @MainActor context is inferred @MainActor-isolated, so entering it
//  off-main trips `dispatch_assert_queue` → crash. Every handler here is marked
//  @Sendable (so it stays genuinely non-isolated) and bridged to async via a
//  continuation. See [[swift6-dispatchworkitem-mainactor-trap]]. Guarded by
//  ExportSaveUITests (crash-survival regression).
//

import Foundation
import Photos

public struct PhotoLibrarySaver {

    public enum SaveError: Error, Equatable {
        case notAuthorized
        case failed
    }

    public init() {}

    /// Saves encoded image data as a new photo asset.
    public func saveImage(_ data: Data) async throws {
        try await performChanges {
            let request = PHAssetCreationRequest.forAsset()
            request.addResource(with: .photo, data: data, options: nil)
        }
    }

    /// Saves a video file (e.g. an exported MP4) as a new video asset. The file is
    /// referenced in place (not moved), so the caller owns cleanup of `url`.
    public func saveVideo(at url: URL) async throws {
        try await performChanges {
            let request = PHAssetCreationRequest.forAsset()
            let options = PHAssetResourceCreationOptions()
            options.shouldMoveFile = false
            request.addResource(with: .video, fileURL: url, options: options)
        }
    }

    // MARK: - Private

    private func performChanges(_ changes: @escaping @Sendable () -> Void) async throws {
        guard await isAuthorized() else { throw SaveError.notAuthorized }
        try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
            PHPhotoLibrary.shared().performChanges(changes) { @Sendable success, error in
                if success { cont.resume() }
                else { cont.resume(throwing: error ?? SaveError.failed) }
            }
        }
    }

    private func isAuthorized() async -> Bool {
        await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .addOnly) { @Sendable status in
                cont.resume(returning: status == .authorized || status == .limited)
            }
        }
    }
}
