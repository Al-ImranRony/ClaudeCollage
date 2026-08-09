//
//  WidgetSnapshot.swift
//  ClaudeCollage
//
//  Step 05 batch C — the data the widgets render.
//
//  A widget extension is its own sandbox: it CANNOT read the app's container. The
//  supported bridge is an App Group, whose entitlement is bound to the developer
//  account and was deferred to Step 06 by owner decision.
//
//  So the container is resolved rather than assumed: the App Group when its
//  entitlement exists, the app's own Application Support directory when it does
//  not. Everything here — writing, reading, trimming, the codec — is finished and
//  tested either way. Until the entitlement lands the app writes a snapshot the
//  widget cannot see, so the widget shows its empty state; adding the App Group in
//  Step 06 makes real data flow with no code change.
//
//  Shared verbatim with the widget target (see project.yml), so both sides encode
//  and decode through exactly one definition.
//

import Foundation

/// One project as a widget needs to know it. Deliberately small: an id to deep
/// link with, a date to sort and label by, and a thumbnail. No collage state —
/// a widget never edits.
public struct WidgetProjectEntry: Codable, Equatable, Sendable, Identifiable {
    public let id: UUID
    public let updatedAt: Date
    /// JPEG, sized for a widget rather than the gallery. Optional because a
    /// project saved before its first render has no thumbnail yet.
    public let thumbnailData: Data?

    public init(id: UUID, updatedAt: Date, thumbnailData: Data?) {
        self.id = id
        self.updatedAt = updatedAt
        self.thumbnailData = thumbnailData
    }
}

public struct WidgetSnapshot: Codable, Equatable, Sendable {
    public let projects: [WidgetProjectEntry]
    public let generatedAt: Date

    public init(projects: [WidgetProjectEntry], generatedAt: Date) {
        self.projects = projects
        self.generatedAt = generatedAt
    }

    public static let empty = WidgetSnapshot(projects: [], generatedAt: .distantPast)
}

/// Reads and writes the snapshot both processes share.
public struct WidgetSnapshotStore: Sendable {

    /// The App Group both targets would join. Referenced by name only — asking for
    /// it is harmless when the entitlement is absent, it simply returns nil.
    public static let appGroupID = "group.com.devron.claudecollage"

    /// The largest grid holds nine, and no widget family shows more than six.
    /// Trimming keeps the file small enough that a widget refresh never stalls.
    public static let maxEntries = 6

    /// Resolved per call rather than stored: `FileManager` is not `Sendable`, and
    /// this store is used from both the app and the widget process.
    private var fileManager: FileManager { .default }

    public init() {}

    /// Where the snapshot lives, preferring the shared container.
    ///
    /// Nil only if even the app's own Application Support directory is
    /// unavailable, which in practice means the process has no writable home.
    public var containerURL: URL? {
        if let shared = fileManager.containerURL(
            forSecurityApplicationGroupIdentifier: Self.appGroupID) {
            return shared
        }
        return fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
    }

    /// True when the App Group is actually available — i.e. when the widget can
    /// really see what the app writes.
    public var isSharedContainerAvailable: Bool {
        fileManager.containerURL(forSecurityApplicationGroupIdentifier: Self.appGroupID) != nil
    }

    public var snapshotURL: URL? {
        containerURL?.appendingPathComponent("widget-snapshot.json")
    }

    /// Writes the newest projects, trimmed. Silently does nothing if there is
    /// nowhere to write — a failed widget refresh must never break a save.
    @discardableResult
    public func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        let trimmed = WidgetSnapshot(
            projects: Array(
                snapshot.projects.sorted { $0.updatedAt > $1.updatedAt }.prefix(Self.maxEntries)),
            generatedAt: snapshot.generatedAt
        )
        do {
            try? fileManager.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(trimmed).write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// The stored snapshot, or `.empty` when absent or unreadable.
    ///
    /// Never throws: a widget with no data shows its empty state, which is a far
    /// better outcome than a widget that fails to render.
    public func read() -> WidgetSnapshot {
        guard let url = snapshotURL,
              let data = try? Data(contentsOf: url),
              let snapshot = try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }
}
