//
//  RecentPhotoProvider.swift
//  Caroullage
//
//  Step 05 batch E — the recent photos behind Home's Suggested Layouts row.
//
//  This is the app's only READ access to the photo library; everything else so
//  far has been add-only (saving exports) or user-driven picking through
//  PHPicker, which needs no permission at all.
//
//  Because of that, authorization is NEVER requested on launch or on a tab
//  appearing. The row shows a single explanatory button, and only tapping it
//  prompts. A system permission dialog the user did not ask for, for a feature
//  they have not seen, is the fastest way to get a permanent "Don't Allow".
//
//  `.readWrite` is deliberately not requested — suggestions only need to read.
//

import Photos
import UIKit

@MainActor
public final class RecentPhotoProvider {

    public enum Access: Equatable {
        /// Never asked. The row offers to explain and request.
        case notDetermined
        /// Granted, in full or for a limited selection — both are usable.
        case authorized
        /// Refused or restricted. The row explains where to change it and never
        /// re-prompts, because iOS will not show the dialog twice anyway.
        case denied
    }

    public init() {}

    public var access: Access {
        Self.map(PHPhotoLibrary.authorizationStatus(for: .readWrite))
    }

    private static func map(_ status: PHAuthorizationStatus) -> Access {
        switch status {
        case .notDetermined: return .notDetermined
        case .authorized, .limited: return .authorized
        default: return .denied
        }
    }

    /// Prompts, once, and reports the outcome.
    public func requestAccess() async -> Access {
        let status = await withCheckedContinuation { (continuation: CheckedContinuation<PHAuthorizationStatus, Never>) in
            PHPhotoLibrary.requestAuthorization(for: .readWrite) { @Sendable status in
                continuation.resume(returning: status)
            }
        }
        return Self.map(status)
    }

    /// The most recent photos, newest first, downsampled.
    ///
    /// Returns empty rather than throwing when access is absent — a suggestion
    /// row that quietly shows nothing is fine; one that errors is not.
    public func recentPhotos(limit: Int = 9) async -> [CGImage] {
        guard access == .authorized else { return [] }

        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        options.fetchLimit = limit
        let assets = PHAsset.fetchAssets(with: .image, options: options)
        guard assets.count > 0 else { return [] }

        var images: [CGImage] = []
        images.reserveCapacity(assets.count)
        for index in 0 ..< assets.count {
            if let image = await requestImage(for: assets.object(at: index)) {
                images.append(image)
            }
        }
        return images
    }

    /// One asset at analysis resolution. Small on purpose: these feed face and
    /// saliency detection and thumbnail previews, never the canvas, so decoding
    /// them large would cost memory for no gain.
    private func requestImage(for asset: PHAsset) async -> CGImage? {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = false   // never stall a row on an iCloud fetch
        options.deliveryMode = .fastFormat
        options.resizeMode = .fast

        return await withCheckedContinuation { (continuation: CheckedContinuation<CGImage?, Never>) in
            let resumed = OnceFlag()
            PHImageManager.default().requestImage(
                for: asset,
                targetSize: CGSize(width: 512, height: 512),
                contentMode: .aspectFit,
                options: options
            ) { @Sendable image, _ in
                // PhotoKit may call back more than once (degraded then full);
                // resuming a continuation twice would trap.
                guard resumed.claim() else { return }
                continuation.resume(returning: image?.cgImage)
            }
        }
    }
}


/// One-shot guard for a callback that may fire more than once.
///
/// PhotoKit can deliver a degraded image and then the full one; resuming a
/// continuation twice traps. Lock-backed rather than actor-isolated because the
/// callback arrives on an arbitrary queue.
private final class OnceFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var used = false

    /// True exactly once, for the first caller.
    func claim() -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !used else { return false }
        used = true
        return true
    }
}
