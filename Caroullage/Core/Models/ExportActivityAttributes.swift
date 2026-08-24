//
//  ExportActivityAttributes.swift
//  Caroullage
//
//  Step 04 slice 6b — the ActivityKit attributes for the export Live Activity.
//
//  Compiled into BOTH the app (which starts/updates the activity) and the widget
//  extension (which renders it on the Lock Screen + Dynamic Island), so it lives in
//  the shared Core layer and is added to the widget target's sources in project.yml.
//
//  Only the value logic here is unit-testable; requesting and rendering a Live
//  Activity is device-only.
//

import ActivityKit
import Foundation

public struct ExportActivityAttributes: ActivityAttributes, Sendable {

    /// The changing part of the activity — pushed on each progress update.
    public struct ContentState: Codable, Hashable, Sendable {
        /// Completed fraction, clamped into 0…1.
        public var fraction: Double
        /// Set on the final update so the UI can show a checkmark before dismissal.
        public var isComplete: Bool

        public init(fraction: Double, isComplete: Bool = false) {
            self.fraction = min(1, max(0, fraction))
            self.isComplete = isComplete
        }

        public var percentText: String { "\(Int((fraction * 100).rounded()))%" }
    }

    /// Fixed for the life of the activity (e.g. "Exporting video…").
    public var title: String

    public init(title: String) { self.title = title }
}
