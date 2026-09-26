//
//  EditorExportFlow.swift
//  Caroullage
//
//  The part of exporting every editor shares: the Universal Export sheet, the
//  credit (taken when the user pays with one, settled on the outcome), the wait
//  (a spinner for a short render, the progress modal for a long cancellable
//  write), handing the file to Photos or the share sheet, the messages, and
//  cleaning the export's temp folder up afterwards. The sequencing itself is
//  `ExportRun`; each editor supplies only its render.
//

import SwiftUI
import UIKit

@MainActor
final class EditorExportFlow {

    /// How the wait is shown while the artifact is made.
    enum Wait {
        /// A short render: a spinner with this message.
        case spinner(String)
        /// A long write: the cancellable progress modal (and its Live Activity).
        case progress
    }

    /// Handed to an editor's render: the export's own temp folder, the user's
    /// cancel, and a progress callback that is safe to call from any queue.
    struct Work: Sendable {
        let folder: URL
        let cancellation: ExportCancellationToken
        let progress: @Sendable (Float) -> Void
    }

    private weak var host: UIViewController?
    private let projectID: () -> UUID

    init(host: UIViewController, projectID: @escaping () -> UUID) {
        self.host = host
        self.projectID = projectID
    }

    // MARK: - The sheet

    func presentSheet(capabilities: ExportCapabilities,
                      onExport: @escaping (ExportOptions, ExportDestination, ExportPayment) -> Void,
                      onBuyCredits: @escaping () -> Void) {
        guard let host else { return }
        let sheet = UniversalExportSheetView(
            capabilities: capabilities,
            onSaveToPhotos: { options, payment in onExport(options, .photos, payment) },
            onQuickShare: { options, payment in onExport(options, .share, payment) },
            onCancel: { [weak host] in host?.dismiss(animated: true) },
            onBuyCredits: onBuyCredits)
        let sheetHost = UIHostingController(rootView: sheet)
        sheetHost.modalPresentationStyle = .pageSheet
        if let presentation = sheetHost.sheetPresentationController {
            presentation.detents = Theme.Layout.sheetDetents(for: host.traitCollection)
            presentation.prefersGrabberVisible = true
        }
        host.present(sheetHost, animated: true)
    }

    // MARK: - One export

    /// Runs one export from the sheet's choice to the message: takes the credit if
    /// the user pays with one, dismisses the sheet, checks `refuseIf`, shows the
    /// wait, makes the artifact, hands it over, and settles the credit on what
    /// actually happened.
    ///
    /// - Parameters:
    ///   - failure: what to say when the render itself fails.
    ///   - savedMessage: the success line after a Photos save.
    func run(payment: ExportPayment,
             destination: ExportDestination,
             wait: Wait,
             failure: ExportRefusal,
             savedMessage: String = String(localized: "Saved to Photos"),
             refuseIf: @escaping () -> ExportRefusal? = { nil },
             produce: @escaping (Work) async throws -> ExportArtifact) {
        guard let host else { return }
        let credit = ExportCreditSession()
        if payment == .credit, !credit.begin() {
            Haptics.error()
            alert(String(localized: "No Credits Left"),
                  String(localized: "Buy a credit or start Premium to export at full quality."))
            return
        }
        host.dismiss(animated: true) { [weak self] in
            guard let self, self.host != nil else {
                credit.failed()
                return
            }
            if let refusal = refuseIf() {
                credit.failed()
                self.alert(refusal.title, refusal.message)
                return
            }
            let folder: URL
            do {
                folder = try ExportFiles.makeFolder()
            } catch {
                credit.failed()
                self.report(.failed(.making, error), destination: destination, failure: failure,
                            savedMessage: savedMessage, folder: nil)
                return
            }
            let token = ExportCancellationToken()
            let waitController = self.presentWait(wait, cancellation: token)
            let progressController = waitController as? ExportProgressViewController
            let work = Work(folder: folder, cancellation: token, progress: { [weak progressController] value in
                progressController?.update(fraction: Double(value))
            })
            Task { @MainActor in
                let outcome = await ExportRun.perform(
                    credit: credit,
                    produce: { try await produce(work) },
                    handOver: { artifact in try await Self.handOver(artifact, to: destination, in: folder) })
                waitController.dismiss(animated: true) {
                    self.report(outcome, destination: destination, failure: failure,
                                savedMessage: savedMessage, folder: folder)
                }
            }
        }
    }

    // MARK: - Private

    private func presentWait(_ wait: Wait, cancellation: ExportCancellationToken) -> UIViewController {
        let controller: UIViewController
        switch wait {
        case .spinner(let message):
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            let indicator = UIActivityIndicatorView(style: .medium)
            indicator.translatesAutoresizingMaskIntoConstraints = false
            indicator.startAnimating()
            alert.view.addSubview(indicator)
            NSLayoutConstraint.activate([
                indicator.centerXAnchor.constraint(equalTo: alert.view.centerXAnchor),
                indicator.bottomAnchor.constraint(equalTo: alert.view.bottomAnchor, constant: -20),
            ])
            controller = alert
        case .progress:
            let progress = ExportProgressViewController()
            progress.onCancel = { cancellation.cancel() }
            controller = progress
        }
        host?.present(controller, animated: true)
        return controller
    }

    /// Photos gets the images or the video; the share sheet gets files, written
    /// here so a failed write settles the credit like a failed save.
    private static func handOver(_ artifact: ExportArtifact, to destination: ExportDestination,
                                 in folder: URL) async throws -> [URL] {
        switch (artifact, destination) {
        case let (.images(images, _, _), .photos):
            let saver = PhotoLibrarySaver()
            for data in images { try await saver.saveImage(data) }
            return []
        case let (.video(url), .photos):
            try await PhotoLibrarySaver().saveVideo(at: url)
            return []
        case let (.images(images, fileExtension, baseName), .share):
            return try ExportFiles.write(images, fileExtension: fileExtension, baseName: baseName, into: folder)
        case let (.video(url), .share):
            return [url]
        }
    }

    private func report(_ outcome: ExportOutcome, destination: ExportDestination, failure: ExportRefusal,
                        savedMessage: String, folder: URL?) {
        guard let host else { return }
        switch outcome {
        case .delivered(let urls) where destination == .share:
            let share = UIActivityViewController(activityItems: urls, applicationActivities: nil)
            share.completionWithItemsHandler = { _, _, _, _ in Self.remove(folder) }
            host.anchorPopover(share) { popover in
                popover.barButtonItem = host.navigationItem.rightBarButtonItems?.first
            }
            host.present(share, animated: true)
            return
        case .delivered:
            host.showSuccess(savedMessage)
            RatingPrompt.exportSucceeded(in: host.view.window?.windowScene)
            ExportEvents.projectExported(projectID())
        case .cancelled:
            // A deliberate cancel isn't a failure: no error alert, and the credit
            // went back because they got no file.
            host.showToast(String(localized: "Export cancelled"))
        case .refused(let refusal):
            alert(refusal.title, refusal.message)
        case .failed(.delivering, let error as PhotoLibrarySaver.SaveError) where error == .notAuthorized:
            alert(String(localized: "No Photos Access"),
                  String(localized: "Enable photo library access in Settings to save your collage."))
        case .failed(.delivering, _) where destination == .share:
            Haptics.error()
            alert(String(localized: "Share failed"), String(localized: "Could not prepare the file to share."))
        case .failed(.delivering, _):
            Haptics.error()
            alert(String(localized: "Save Failed"), String(localized: "Couldn't save to Photos."))
        case .failed(.making, _):
            Haptics.error()
            alert(failure.title, failure.message)
        }
        Self.remove(folder)
    }

    private func alert(_ title: String, _ message: String) {
        let alert = UIAlertController(title: title, message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: String(localized: "OK"), style: .default))
        host?.present(alert, animated: true)
    }

    private static func remove(_ folder: URL?) {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}
