//
//  ExportProgress.swift
//  ClaudeCollage
//
//  Step 04 slice 6a — the export progress UX, as values.
//
//  `ExportCancellationToken` is the thread-safe flag the write loops poll: the
//  exporter runs its pull loop on a private queue while the Cancel button is tapped
//  on the main actor, so the flag needs a lock rather than plain isolation. The
//  loops respond by calling `AVAssetReader.cancelReading()` /
//  `AVAssetWriter.cancelWriting()` and throwing `ComposerError.cancelled`.
//
//  `ExportProgressState` holds the plan's presentation rules — indeterminate
//  spinner under 3 s, a 0–100% bar beyond it, a "Processing…" label carrying
//  elapsed time — as pure logic, so they're unit-tested instead of eyeballed.
//

import Foundation

/// A cancellation flag shared between the UI (which sets it) and an export's
/// private write queue (which polls it).
public final class ExportCancellationToken: @unchecked Sendable {

    private let lock = NSLock()
    private var cancelled = false

    public init() {}

    public var isCancelled: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cancelled
    }

    /// Requests cancellation. Idempotent, and safe from any thread.
    public func cancel() {
        lock.lock()
        cancelled = true
        lock.unlock()
    }
}

/// What the export progress UI should currently display.
public struct ExportProgressState: Equatable, Sendable {

    /// Completed fraction, clamped into 0…1.
    public let fraction: Double
    /// Seconds since the export began.
    public let elapsed: TimeInterval
    /// True once the user has tapped Cancel but the writer hasn't torn down yet.
    public let isCancelling: Bool

    /// Exports shorter than this stay on an indeterminate spinner — a bar that
    /// appears and vanishes within a second reads as a glitch.
    public static let progressBarThreshold: TimeInterval = 3

    public init(fraction: Double = 0, elapsed: TimeInterval = 0, isCancelling: Bool = false) {
        self.fraction = min(1, max(0, fraction))
        self.elapsed = max(0, elapsed)
        self.isCancelling = isCancelling
    }

    /// Indeterminate spinner for a quick export; a determinate bar once it's clear
    /// the export is a long one.
    public var showsProgressBar: Bool { elapsed >= Self.progressBarThreshold }

    public var percentText: String { "\(Int((fraction * 100).rounded()))%" }

    public var statusText: String {
        guard !isCancelling else { return "Cancelling…" }
        return "Processing… \(Self.timeText(elapsed))"
    }

    private static func timeText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
