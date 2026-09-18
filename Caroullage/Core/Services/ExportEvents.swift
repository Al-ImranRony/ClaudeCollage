//
//  ExportEvents.swift
//  Caroullage
//
//  Step 06 review fix — "this project was exported", said once, heard by
//  whoever needs it.
//
//  The unfinished-project reminder asks the store for projects that were
//  never exported, which depends on `ProjectStore.markExported` being called
//  when an export succeeds. The editors know their project id and the moment
//  of success but deliberately do not hold the store; the coordinator holds
//  the store but never sees an export. A notification is the seam between
//  them, the same way `RatingPrompt` hears about the success beat.
//

import Foundation

public enum ExportEvents {

    /// Posted after an export produced a file. `userInfo[projectIDKey]` is the
    /// project's `UUID`.
    public static let didExportProject = Notification.Name("Caroullage.didExportProject")
    public static let projectIDKey = "projectID"

    @MainActor
    public static func projectExported(_ id: UUID) {
        NotificationCenter.default.post(
            name: didExportProject, object: nil, userInfo: [projectIDKey: id])
    }

    public static func projectID(from notification: Notification) -> UUID? {
        notification.userInfo?[projectIDKey] as? UUID
    }
}
