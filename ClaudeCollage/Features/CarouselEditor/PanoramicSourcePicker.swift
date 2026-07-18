//
//  PanoramicSourcePicker.swift
//  ClaudeCollage
//
//  Step 03b slice 5 — picks the single wide photo a panoramic carousel is split
//  from. A tiny NSObject wrapper around PHPicker (the coordinator isn't a
//  responder), loading + downsampling off the main thread exactly like the grid
//  editor's import (never decode a full-resolution photo into memory). A larger
//  downsample cap than the display default keeps each split slice reasonably crisp.
//

import PhotosUI
import UIKit
import UniformTypeIdentifiers

final class PanoramicSourcePicker: NSObject, PHPickerViewControllerDelegate {

    /// Longest-edge cap for the panoramic source — bigger than the display default so
    /// N slices still carry detail.
    private let sourceMaxDimension: CGFloat = 3200

    private let completion: (CGImage?) -> Void

    init(completion: @escaping (CGImage?) -> Void) {
        self.completion = completion
    }

    /// A single-image PHPicker wired to this object.
    func makePicker() -> PHPickerViewController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = self
        return picker
    }

    func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
        picker.dismiss(animated: true)
        guard let provider = results.first?.itemProvider else {
            completion(nil)
            return
        }
        // Mirror the grid editor's import: the @Sendable load closure captures only
        // [weak self] + Sendable locals; the non-Sendable `completion` is touched only
        // after hopping back to the main queue.
        let maxDimension = sourceMaxDimension
        provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { [weak self] data, _ in
            let image = data.flatMap { ImageDownsampler.downsample(data: $0, maxDimension: maxDimension) }
            DispatchQueue.main.async {
                self?.completion(image)
            }
        }
    }
}
