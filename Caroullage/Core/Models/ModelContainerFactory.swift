//
//  ModelContainerFactory.swift
//  Caroullage
//
//  Builds the shared SwiftData ModelContainer used across the app.
//
//  A store that will not open (a corrupt file, a failed migration) used to be
//  swapped for an in-memory one without a word: the library looked empty AND
//  everything made afterwards vanished on the next launch. Now the unreadable
//  files are set aside — kept, never deleted — and a fresh store opens on disk
//  in their place. `PersistenceDurabilityTests` pins both halves.
//
//  The schema is versioned (`CaroullageSchema.swift`) and opened through its
//  migration plan. A store written before versioning — every development
//  install up to v1, with the retired CollageCell table — opens through the
//  plan directly: SwiftData infers the lightweight step to V1 on its own
//  (`PersistenceDurabilityTests` pins it with a real pre-versioning store).
//

import Foundation
import OSLog
import SwiftData

public enum ModelContainerFactory {

    static let schema = Schema(versionedSchema: CaroullageSchemaV1.self)

    private static let log = Logger(subsystem: "com.devron.caroullage", category: "Persistence")

    /// The shared production container, at SwiftData's default location
    /// (`Application Support/default.store`), so existing installs keep their store.
    @MainActor
    public static func makeShared() -> ModelContainer {
        makeContainer(storeURL: URL.applicationSupportDirectory.appendingPathComponent("default.store"))
    }

    /// Opens the on-disk store at `storeURL`. When it cannot be opened, its files
    /// move into `Recovered/<timestamp>/` beside it and a fresh store opens at the
    /// same URL, so the user's next projects survive a relaunch and the old ones
    /// can still be recovered. In-memory is the last resort, only if even a fresh
    /// store fails (a full disk, a read-only container).
    @MainActor
    static func makeContainer(storeURL: URL, fileManager: FileManager = .default) -> ModelContainer {
        do {
            return try openOnDisk(at: storeURL)
        } catch {
            log.fault("Store failed to open: \(String(describing: error), privacy: .public)")
        }
        do {
            let folder = try setAsideStoreFiles(at: storeURL, fileManager: fileManager)
            log.fault("Unreadable store kept at \(folder.path, privacy: .public); opening a fresh one")
            return try openOnDisk(at: storeURL)
        } catch {
            log.fault("A fresh store failed too; this session will not persist: \(String(describing: error), privacy: .public)")
        }
        // swiftlint:disable:next force_try
        return try! ModelContainer(
            for: schema,
            configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
        )
    }

    private static func openOnDisk(at url: URL) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: CaroullageMigrationPlan.self,
                           configurations: [ModelConfiguration(schema: schema, url: url)])
    }

    /// Moves the store, its SQLite sidecars (`-wal`, `-shm`) and SwiftData's
    /// external-storage folder (`.<name>_SUPPORT`) into a dated folder under
    /// `Recovered/` next to it, and returns that folder.
    private static func setAsideStoreFiles(at storeURL: URL, fileManager: FileManager) throws -> URL {
        let parent = storeURL.deletingLastPathComponent()
        let stamp = ISO8601DateFormatter().string(from: Date()).replacingOccurrences(of: ":", with: "-")
        let folder = parent
            .appendingPathComponent("Recovered", isDirectory: true)
            .appendingPathComponent(stamp, isDirectory: true)
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true)
        let name = storeURL.lastPathComponent
        let support = ".\(storeURL.deletingPathExtension().lastPathComponent)_SUPPORT"
        for file in try fileManager.contentsOfDirectory(atPath: parent.path)
        where file.hasPrefix(name) || file == support {
            try fileManager.moveItem(at: parent.appendingPathComponent(file),
                                    to: folder.appendingPathComponent(file))
        }
        return folder
    }
}
