import SwiftData

enum AnvilModelContainerFactory {
    static func make(isRunningTests: Bool) throws -> ModelContainer {
        if isRunningTests {
            let config = ModelConfiguration(isStoredInMemoryOnly: true)
            return try make(configuration: config)
        }

        try AnvilPaths.migrateLegacyDataIfNeeded()
        let locations = try AnvilPersistentStoreLocations.live()
        try AnvilPersistentStorePreparer(locations: locations).prepare()
        return try make(configuration: ModelConfiguration(url: locations.storeURL))
    }

    static func make(configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(
            for: Schema(versionedSchema: AnvilSchemaV7.self),
            migrationPlan: AnvilSchemaMigrationPlan.self,
            configurations: configuration
        )
    }
}
