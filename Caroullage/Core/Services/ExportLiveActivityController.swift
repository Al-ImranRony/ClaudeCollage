//
//  ExportLiveActivityController.swift
//  Caroullage
//
//  Step 04 slice 6b — starts / updates / ends the export Live Activity.
//
//  Every ActivityKit call is guarded: if the user has Live Activities disabled (or
//  the platform can't provide them — the simulator, a headless run), every method
//  is a silent no-op, so an export behaves exactly as it did before this slice. A
//  failed `request` is swallowed the same way. The activity therefore can never
//  break or block an export — it's purely additive Lock Screen / Dynamic Island
//  chrome. Its rendering is verified by on-device manual QA.
//

import ActivityKit
import Foundation

@MainActor
final class ExportLiveActivityController {

    private var activity: Activity<ExportActivityAttributes>?

    /// Begins the activity if the platform allows it and one isn't already running.
    func start(title: String, fraction: Double = 0) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled, activity == nil else { return }
        let attributes = ExportActivityAttributes(title: title)
        let state = ExportActivityAttributes.ContentState(fraction: fraction)
        activity = try? Activity.request(
            attributes: attributes,
            content: ActivityContent(state: state, staleDate: nil))
    }

    /// Pushes a new progress value to a running activity. `ActivityContent` is not
    /// Sendable, so it's built inside the task — only the Sendable `activity` handle
    /// and `fraction` cross the boundary.
    func update(fraction: Double) {
        guard let activity else { return }
        let box = ActivityBox(activity)
        Task {
            let state = ExportActivityAttributes.ContentState(fraction: fraction)
            await box.activity.update(ActivityContent(state: state, staleDate: nil))
        }
    }

    /// Marks the activity complete and dismisses it immediately.
    func end() {
        guard let activity else { return }
        self.activity = nil
        let box = ActivityBox(activity)
        Task {
            let final = ExportActivityAttributes.ContentState(fraction: 1, isComplete: true)
            await box.activity.end(ActivityContent(state: final, staleDate: nil),
                                   dismissalPolicy: .immediate)
        }
    }

    /// Carries the non-Sendable `Activity` handle into the update task — the same
    /// box idiom used across the codebase for non-Sendable system objects. The
    /// handle is only touched inside the task, never concurrently.
    private struct ActivityBox: @unchecked Sendable {
        let activity: Activity<ExportActivityAttributes>
        init(_ activity: Activity<ExportActivityAttributes>) { self.activity = activity }
    }
}
