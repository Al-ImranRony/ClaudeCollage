//
//  VideoAssetLoader.swift
//  ClaudeCollage
//
//  Step 04 slice 3 — turns a picked video PHAsset into a playable AVAsset the
//  composition builder can place into a cell (the plan's "AVURLAsset from PHAsset
//  via PHImageManager.requestAVAsset").
//
//  PHImageManager invokes its result handler on a BACKGROUND queue. Under Swift 6
//  complete concurrency the handler must be genuinely non-isolated (@Sendable) or
//  it inherits @MainActor and traps off-main — the same trap PhotoLibrarySaver /
//  PanoramicSourcePicker dodge. See [[swift6-dispatchworkitem-mainactor-trap]].
//  AVAsset is not Sendable, so it's carried back across the continuation inside an
//  @unchecked Sendable box and unwrapped in the async context.
//
//  Requires the Photos library, so — like PanoramicSourcePicker — it's verified by
//  on-device manual QA, not a headless unit test.
//

import AVFoundation
import Photos

public struct VideoAssetLoader {

    public enum LoadError: Error, Equatable {
        case unavailable
    }

    public init() {}

    /// Loads a playable `AVAsset` for a video `PHAsset`. Network access is allowed
    /// so iCloud-backed videos download on demand; the highest-quality version is
    /// requested (export/preview both want full fidelity).
    public func loadAsset(
        for phAsset: PHAsset,
        manager: PHImageManager = .default()
    ) async throws -> AVAsset {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.version = .current

        let box = try await withCheckedThrowingContinuation { (cont: CheckedContinuation<SendableBox<AVAsset>, Error>) in
            manager.requestAVAsset(forVideo: phAsset, options: options) { @Sendable asset, _, _ in
                if let asset {
                    cont.resume(returning: SendableBox(asset))
                } else {
                    cont.resume(throwing: LoadError.unavailable)
                }
            }
        }
        return box.value
    }

    /// Crosses a non-Sendable value back through the continuation. Safe here: the
    /// AVAsset is produced inside the handler and handed off exactly once.
    private struct SendableBox<T>: @unchecked Sendable {
        let value: T
        init(_ value: T) { self.value = value }
    }
}
