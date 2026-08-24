//
//  ModelContainerFactory.swift
//  Caroullage
//
//  Builds the shared SwiftData ModelContainer used across the app.
//  Stub for Step 00 — verified by app launch.
//

import Foundation
import SwiftData

public enum ModelContainerFactory {

    /// Returns the shared production ModelContainer.
    /// Falls back to an in-memory container if the on-disk store cannot be opened
    /// (e.g. running unit tests or recovering from a corrupted migration).
    @MainActor
    public static func makeShared() -> ModelContainer {
        let schema = Schema([
            CollageProject.self,
            CollageCell.self,
            PersonalSticker.self,
        ])
        do {
            let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            #if DEBUG
            print("[Caroullage] On-disk ModelContainer failed (\(error)); using in-memory store.")
            #endif
            // Safe fallback so the app still launches.
            // swiftlint:disable:next force_try
            return try! ModelContainer(
                for: schema,
                configurations: [ModelConfiguration(schema: schema, isStoredInMemoryOnly: true)]
            )
        }
    }
}
