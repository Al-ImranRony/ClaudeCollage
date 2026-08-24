//
//  StartEditingPhotoPicker.swift
//  Caroullage
//
//  Step 04.5 batch C — the photo picker behind the floating "+".
//
//  The "+" is photos-first: pick images, get a collage already filled, then change
//  the layout in the editor if you want to. That means a MULTI-select picker,
//  unlike the single-image `PanoramicSourcePicker` and the grid editor's
//  one-cell-at-a-time import — this is the batch import Step 01 left as a
//  follow-up.
//
//  Same NSObject-wrapper shape as `PanoramicSourcePicker` (the coordinator isn't a
//  responder), and the same off-main downsample so a full-resolution photo is never
//  decoded into memory. Results are reassembled in PICK ORDER: item providers finish
//  in whatever order they load, and a collage whose cells are shuffled relative to
//  what the user chose would look like a bug.
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class StartEditingPhotoPicker: NSObject, PHPickerViewControllerDelegate {

    /// The largest stock grid holds nine cells, so there is nothing to do with a
    /// tenth photo.
    static let selectionLimit = 9

    private let completion: ([CGImage]) -> Void

    init(completion: @escaping ([CGImage]) -> Void) {
        self.completion = completion
    }

    func makePicker() -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = Self.selectionLimit
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        return picker
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard !results.isEmpty else {
            completion([])          // cancelled
            return
        }

        // Slot each decoded image back into its original index, so load order can't
        // reshuffle the collage.
        let providers = results.map(\.itemProvider)
        let box = ResultBox(count: providers.count)
        let group = DispatchGroup()

        for (index, provider) in providers.enumerated() {
            group.enter()
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                let image = data.flatMap { ImageDownsampler.downsample(data: $0) }
                box.set(image, at: index)
                group.leave()
            }
        }

        group.notify(queue: .main) { [weak self] in
            self?.completion(box.ordered())
        }
    }
}

/// Collects results from the concurrent provider loads. `PHPickerResult`'s loader
/// calls back on an arbitrary queue, so the writes need their own lock rather than
/// actor isolation — the same reason `ExportCancellationToken` is lock-backed.
private final class ResultBox: @unchecked Sendable {

    private let lock = NSLock()
    private var images: [CGImage?]

    init(count: Int) {
        images = Array(repeating: nil, count: count)
    }

    func set(_ image: CGImage?, at index: Int) {
        lock.lock()
        defer { lock.unlock() }
        guard images.indices.contains(index) else { return }
        images[index] = image
    }

    /// Decoded images in pick order; anything that failed to load is dropped rather
    /// than leaving a hole in the collage.
    func ordered() -> [CGImage] {
        lock.lock()
        defer { lock.unlock() }
        return images.compactMap { $0 }
    }
}
