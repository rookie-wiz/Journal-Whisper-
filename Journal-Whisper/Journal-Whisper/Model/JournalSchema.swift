//
//  JournalSchema.swift
//  Journal-Whisper
//
//  Versioned SwiftData schema, set up before the first TestFlight build so
//  later changes can migrate users' journals safely.
//
//  V1 is the first shipped schema. To change a model after shipping:
//  1. Move a frozen copy of the current models into `SchemaV1` (nested types).
//  2. Add `SchemaV2` with the new models and point the app's typealiases at it.
//  3. Add V2 to `JournalMigrationPlan.schemas` and a lightweight or custom
//     `MigrationStage` to `stages`.
//

import Foundation
import SwiftData

enum SchemaV1: VersionedSchema {
    static var versionIdentifier: Schema.Version { Schema.Version(1, 0, 0) }
    static var models: [any PersistentModel.Type] { [JournalEntry.self, WeeklySummary.self] }
}

enum JournalMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [SchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

extension ModelContainer {
    /// The app's container: versioned schema plus migration plan.
    static func journal(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV1.self)
        // No iCloud sync, ever: the privacy policy promises the journal stays on
        // the device. Explicit, so adding an iCloud capability later can't turn it on.
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: JournalMigrationPlan.self, configurations: [configuration])
    }
}
