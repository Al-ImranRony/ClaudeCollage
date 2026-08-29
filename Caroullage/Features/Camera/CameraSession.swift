//
//  CameraSession.swift
//  Caroullage
//
//  Step 06 UI pass — the capture stack, kept away from the view controller.
//
//  `AVCaptureSession` and its outputs are not `Sendable`, and under Swift 6 that
//  makes them awkward to own from a `@MainActor` view controller: every touch
//  has to cross an isolation boundary that AVFoundation does not model. So they
//  live here instead, confined to one queue, behind two callbacks — a filtered
//  frame for the preview, and a still for the shutter.
//
//  `@unchecked Sendable` is the honest label: the compiler cannot see the
//  confinement, but every stored property is only ever touched on `queue`.
//

import AVFoundation
import CoreImage
import CoreGraphics

final class CameraSession: NSObject, @unchecked Sendable {

    /// Whether this device has a camera at all. False in the simulator, which is
    /// a supported state rather than a failure.
    static var isAvailable: Bool {
        AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) != nil
    }

    /// A live frame, already filtered, ready to draw.
    var onFrame: (@Sendable (CGImage) -> Void)?
    /// A full-resolution still from the shutter, already filtered.
    var onPhoto: (@Sendable (CGImage) -> Void)?

    private let session = AVCaptureSession()
    private let photoOutput = AVCapturePhotoOutput()
    private let videoOutput = AVCaptureVideoDataOutput()
    private let queue = DispatchQueue(label: "com.devron.caroullage.camera")
    private let context = CIContext(options: [.useSoftwareRenderer: false])

    private let lock = NSLock()
    private var settings = CellFilters()

    /// The look applied to both the preview and the next still, so what the user
    /// framed is what they get.
    func setFilter(_ filters: CellFilters) {
        lock.lock()
        settings = filters
        lock.unlock()
    }

    private var currentSettings: CellFilters {
        lock.lock()
        defer { lock.unlock() }
        return settings
    }

    // MARK: - Lifecycle

    func start() {
        queue.async { [self] in
            if session.inputs.isEmpty { configure() }
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    func stop() {
        queue.async { [self] in
            guard session.isRunning else { return }
            session.stopRunning()
        }
    }

    func capturePhoto() {
        queue.async { [self] in
            guard session.isRunning else { return }
            photoOutput.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
        }
    }

    private func configure() {
        session.beginConfiguration()
        session.sessionPreset = .photo

        if let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
           let input = try? AVCaptureDeviceInput(device: device),
           session.canAddInput(input) {
            session.addInput(input)
        }
        if session.canAddOutput(photoOutput) {
            session.addOutput(photoOutput)
        }
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA,
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(self, queue: queue)
        if session.canAddOutput(videoOutput) {
            session.addOutput(videoOutput)
        }
        session.commitConfiguration()
    }
}

// MARK: - Live frames

extension CameraSession: AVCaptureVideoDataOutputSampleBufferDelegate {

    func captureOutput(
        _ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        guard let onFrame, let buffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        let source = CIImage(cvPixelBuffer: buffer)
        let filtered = ImageFilterProcessor.shared.applyToCIImage(currentSettings, source)
        guard let image = context.createCGImage(filtered, from: filtered.extent) else { return }
        onFrame(image)
    }
}

// MARK: - Stills

extension CameraSession: AVCapturePhotoCaptureDelegate {

    func photoOutput(
        _ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?
    ) {
        guard error == nil, let raw = photo.cgImageRepresentation() else { return }
        // The still goes through the same filter as the preview did.
        onPhoto?(ImageFilterProcessor.shared.apply(currentSettings, to: raw))
    }
}
