//
//  CaroullageSchema.swift
//  Caroullage
//
//  The SwiftData schema, versioned from v1 so every later change is a
//  migration stage rather than a guess.
//
//  V1 holds only what is stored as plain columns: `CollageProject` (editor
//  state lives in JSON blobs, `gridStateData` / `carouselData` / `videoData`)
//  and `PersonalSticker`. No live editor type is a column, so the editors can
//  change freely without touching the schema.
//
//  To change a model later: copy V1's models, as they are today, into a frozen
//  `CaroullageSchemaV1` namespace; make the live classes `CaroullageSchemaV2`;
//  append V2 and a stage (lightweight when SwiftData can infer it) to the plan;
//  and add a fixture store written by V1 to `PersistenceDurabilityTests`, the
//  way `Fixtures/UnversionedStore` pins the step from pre-versioning stores.
//

import Foundation
import SwiftData

public enum CaroullageSchemaV1: VersionedSchema {
    public static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }

    public static var models: [any PersistentModel.Type] {
        [CollageProject.self, PersonalSticker.self]
    }
}

public enum CaroullageMigrationPlan: SchemaMigrationPlan {
    public static var schemas: [any VersionedSchema.Type] { [CaroullageSchemaV1.self] }

    public static var stages: [MigrationStage] { [] }
}
