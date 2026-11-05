import Foundation
import SwiftData

/// Opens the versioned store. A store that fails to open is reported, never reset.
enum PersistenceController {
    static func defaultStoreURL() throws -> URL {
        try FileManager.default
            .url(for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
            .appendingPathComponent("SpotGear", isDirectory: true)
            .appendingPathComponent("SpotGear.store", isDirectory: false)
    }

    static func makeContainer(storeURL: URL) throws -> ModelContainer {
        try FileManager.default.createDirectory(
            at: storeURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, url: storeURL, allowsSave: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: SpotGearMigrationPlan.self, configurations: [configuration])
    }

    static func makeInMemoryContainer() throws -> ModelContainer {
        let schema = Schema(versionedSchema: SchemaV2.self)
        let configuration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        return try ModelContainer(for: schema, migrationPlan: SpotGearMigrationPlan.self, configurations: [configuration])
    }
}
