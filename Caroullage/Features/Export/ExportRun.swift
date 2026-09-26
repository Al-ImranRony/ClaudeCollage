//
//  ExportRun.swift
//  Caroullage
//
//  The sequence every export shares, free of UIKit so it is testable: make the
//  artifact, hand it over (to Photos, or as files for the share sheet), and
//  settle the credit on what actually happened. `EditorExportFlow` wraps it in
//  the sheet, the wait and the messages; each editor supplies only its render.
//
//  The three editors used to carry their own copies, and they had drifted — the
//  carousel's image-set share never took the credit at all.
//

import Foundation

/// What an editor hands over once its render is done.
enum ExportArtifact {
    /// Encoded images, in order: one for a collage, one per frame for a carousel.
    case images([Data], fileExtension: String, baseName: String)
    /// A finished video file.
    case video(URL)

    var itemCount: Int {
        switch self {
        case .images(let images, _, _): images.count
        case .video: 1
        }
    }
}

enum ExportDestination: Equatable {
    case photos
    case share
}

/// An export declined for a reason the user can fix ("Add a video to a slot
/// first"). The credit goes back and the message is shown as it is.
struct ExportRefusal: Error, Equatable {
    let title: String
    let message: String
}

/// A render that produced nothing to hand over.
struct ExportRenderFailed: Error {}

/// How one export ended.
enum ExportOutcome {
    enum Stage { case making, delivering }

    /// Handed over. For a share, the files to offer — the credit is still held
    /// until the sheet closes (`settle(after:)`); empty after a Photos save.
    /// `items` is how many images (or videos) went out, for the message.
    case delivered([URL], items: Int)
    case cancelled
    case refused(ExportRefusal)
    case failed(Stage, Error)
}

@MainActor
enum ExportRun {

    /// Runs one export against a credit session the caller has already begun
    /// (or left idle, for an entitled export). A Photos save consumes the credit
    /// when it completes. A share only writes the files the sheet will offer —
    /// the user has nothing yet — so the credit stays held for the caller to
    /// settle when the sheet closes. Every failure gives it back.
    static func perform(
        credit: ExportCreditSession,
        destination: ExportDestination,
        produce: () async throws -> ExportArtifact,
        handOver: (ExportArtifact) async throws -> [URL]
    ) async -> ExportOutcome {
        let artifact: ExportArtifact
        do {
            artifact = try await produce()
        } catch let refusal as ExportRefusal {
            credit.failed()
            return .refused(refusal)
        } catch {
            if isCancellation(error) {
                credit.cancelled()
                return .cancelled
            }
            credit.failed()
            return .failed(.making, error)
        }

        do {
            switch destination {
            case .photos:
                try await credit.deliver { _ = try await handOver(artifact) }
                return .delivered([], items: artifact.itemCount)
            case .share:
                return .delivered(try await handOver(artifact), items: artifact.itemCount)
            }
        } catch {
            credit.failed()            // latched: a no-op when deliver already refunded
            return isCancellation(error) ? .cancelled : .failed(.delivering, error)
        }
    }

    static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let composer = error as? VideoComposer.ComposerError, case .cancelled = composer { return true }
        return false
    }
}

/// How the share sheet ended, read from its completion handler. iOS calls the
/// handler when an activity ends, and leaves the sheet on screen when that
/// activity was cancelled — so only some calls mean the sheet is done.
enum ShareSheetEnding: Equatable {
    /// An activity finished: the user has the file.
    case shared
    /// The sheet went away without sharing.
    case dismissed
    /// An activity was cancelled; the sheet is still open for another choice.
    case stillOpen

    init(activityChosen: Bool, completed: Bool) {
        if completed { self = .shared } else { self = activityChosen ? .stillOpen : .dismissed }
    }
}

extension ExportCreditSession {
    /// Settles a credit held across a share sheet: kept once something was
    /// shared, given back when the sheet is dismissed, untouched while it is
    /// still open.
    func settle(after ending: ShareSheetEnding) {
        switch ending {
        case .shared: succeeded()
        case .dismissed: failed()
        case .stillOpen: break
        }
    }
}

/// Where an export's files live: one fresh folder per export under the temp
/// directory, removed once Photos has the file or the share sheet is done.
enum ExportFiles {

    enum WriteError: Error { case nothingToWrite }

    static func makeFolder() throws -> URL {
        let folder = FileManager.default.temporaryDirectory
            .appendingPathComponent("Exports", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    /// Writes encoded images for the share sheet, in order: a single image under
    /// its plain name, several as `<baseName>_01`, `_02`, … so apps that sort by
    /// name keep a carousel in sequence.
    static func write(_ images: [Data], fileExtension: String, baseName: String, into folder: URL) throws -> [URL] {
        guard !images.isEmpty else { throw WriteError.nothingToWrite }
        return try images.enumerated().map { index, data in
            let name = images.count == 1 ? baseName : String(format: "%@_%02d", baseName, index + 1)
            let url = folder.appendingPathComponent(name).appendingPathExtension(fileExtension)
            try data.write(to: url, options: .atomic)
            return url
        }
    }
}
