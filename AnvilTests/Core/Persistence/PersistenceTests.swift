import Foundation
import SwiftData
import Testing
@testable import Anvil

struct PersistenceTests {
    @MainActor
    @Test
    func inMemoryModelContainerSupportsCurrentSchema() throws {
        let container = try AnvilModelContainerFactory.make(isRunningTests: true)
        let context = ModelContext(container)

        let provider = ProviderConfig(
            identifier: "local",
            displayName: "Local",
            baseURLString: "",
            authMode: .none,
            origin: .builtIn
        )
        context.insert(provider)

        let tool = Tool(name: "Clipboard Cleaner", packageRootPath: "/tmp/clipboard-cleaner")
        context.insert(tool)

        let model = ModelConfig(
            identifier: "local.apple-foundation",
            displayName: "Apple Foundation Model",
            providerIdentifier: provider.identifier,
            source: .appleFoundation,
            installState: .builtIn
        )
        context.insert(model)

        try context.save()

        #expect(try context.fetch(FetchDescriptor<Tool>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ModelConfig>()).count == 1)
        #expect(try context.fetch(FetchDescriptor<ProviderConfig>()).count == 1)
        #expect(provider.openAICompatibleAPIVariant == .chatCompletions)
        #expect(tool.executableName == "ClipboardCleaner")
        #expect(tool.bundleIdentifier.hasPrefix("com.anvil.generated.clipboardcleaner."))
        #expect(tool.sandboxEnabled)
        #expect(tool.appBundleURL.lastPathComponent == "Clipboard Cleaner.app")
    }

    @MainActor
    @Test
    func diskBackedModelContainerReopensCurrentToolSchema() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("anvil.sqlite")
        let config = ModelConfiguration(url: storeURL)

        do {
            let container = try ModelContainer(
                for: Tool.self,
                ModelConfig.self,
                ProviderConfig.self,
                configurations: config
            )
            let context = ModelContext(container)
            context.insert(
                Tool(
                    name: "Incomplete",
                    category: .music,
                    packageRootPath: "/tmp/incomplete",
                    generationState: .stopped,
                    generationPhase: .generatingSource,
                    generationMode: .create,
                    pendingPrompt: "Build a resumable app"
                )
            )
            try context.save()
        }

        do {
            let container = try AnvilModelContainerFactory.make(configuration: config)
            let context = ModelContext(container)
            let tool = try #require(try context.fetch(FetchDescriptor<Tool>()).first)
            #expect(tool.generationState == ToolGenerationState.stopped)
            #expect(tool.generationPhase == ToolGenerationPhase.generatingSource)
            #expect(tool.generationMode == ToolGenerationMode.create)
            #expect(tool.pendingPrompt == "Build a resumable app")
            #expect(tool.category == .music)
            #expect(container.schema.version == AnvilSchemaV7.versionIdentifier)
            #expect(container.migrationPlan != nil)
        }
    }

    @MainActor
    @Test
    func v5ToolsMigrateWithUtilitiesCategory() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ModelConfiguration(
            url: root.appendingPathComponent("anvil.sqlite")
        )
        let toolID = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: AnvilSchemaV5.self),
                configurations: config
            )
            let context = ModelContext(container)
            context.insert(
                AnvilSchemaV5.Tool(
                    id: toolID,
                    name: "Legacy Utility",
                    packageRootPath: "/tmp/legacy-utility"
                )
            )
            try context.save()
        }

        let container = try AnvilModelContainerFactory.make(configuration: config)
        let context = ModelContext(container)
        let tool = try #require(
            try context.fetch(FetchDescriptor<Tool>()).first { $0.id == toolID }
        )

        #expect(tool.category == .utilities)
    }

    @MainActor
    @Test
    func v6ModelsMigrateWithUnknownContextWindow() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ModelConfiguration(
            url: root.appendingPathComponent("anvil.sqlite")
        )
        let modelID = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: AnvilSchemaV6.self),
                configurations: config
            )
            let context = ModelContext(container)
            context.insert(
                AnvilSchemaV6.ModelConfig(
                    id: modelID,
                    identifier: "openai/gpt-5.5",
                    displayName: "GPT-5.5",
                    providerIdentifier: "ironsmith",
                    source: .remote,
                    installState: .installed
                )
            )
            try context.save()
        }

        let container = try AnvilModelContainerFactory.make(configuration: config)
        let context = ModelContext(container)
        let model = try #require(
            try context.fetch(FetchDescriptor<ModelConfig>()).first { $0.id == modelID }
        )

        #expect(container.schema.version == AnvilSchemaV7.versionIdentifier)
        #expect(model.contextWindowTokens == nil)
    }

    @MainActor
    @Test
    func v1StoreMigratesToCurrentSchemaAndDeletesLegacyLocalModels() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("anvil.sqlite")
        let config = ModelConfiguration(url: storeURL)
        let toolID = UUID()
        let modelID = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: AnvilSchemaV1.self),
                configurations: config
            )
            let context = ModelContext(container)
            let provider = AnvilSchemaV1.ProviderConfig(
                identifier: "local",
                displayName: "Local",
                baseURLString: "",
                authMode: .none,
                origin: .builtIn
            )
            let tool = AnvilSchemaV1.Tool(
                id: toolID,
                name: "Menu Timer",
                sandboxEnabled: false,
                appKind: .menuBar,
                menuBarSystemImage: "timer",
                sandboxPermissions: GeneratedAppSandboxPermissions([.outgoingConnections]),
                resourcePermissions: GeneratedAppResourcePermissions([.camera, .microphone]),
                packageRootPath: "/tmp/menu-timer",
                generationState: .stopped,
                generationPhase: .generatingSource,
                generationMode: .edit,
                pendingPrompt: "Make it better"
            )
            let model = AnvilSchemaV1.ModelConfig(
                id: modelID,
                identifier: "mlx.example",
                displayName: "Example MLX",
                providerIdentifier: provider.identifier,
                source: .mlx,
                installState: .installed
            )
            context.insert(provider)
            context.insert(tool)
            context.insert(model)
            try context.save()
        }

        let container = try AnvilModelContainerFactory.make(configuration: config)
        let context = ModelContext(container)
        let tool = try #require(try context.fetch(FetchDescriptor<Tool>()).first)
        let models = try context.fetch(FetchDescriptor<ModelConfig>())

        #expect(container.schema.version == AnvilSchemaV7.versionIdentifier)
        #expect(tool.id == toolID)
        #expect(tool.appKind == .menuBar)
        #expect(tool.generationState == .stopped)
        #expect(tool.generationPhase == .generatingSource)
        #expect(tool.generationMode == .edit)
        #expect(tool.pendingPrompt == "Make it better")
        #expect(tool.storedSandboxPermissions?.enabled == [.outgoingConnections])
        #expect(tool.storedResourcePermissions?.enabled == [.camera, .microphone])
        #expect(tool.storeId == nil)
        #expect(tool.storeAppId == nil)
        #expect(tool.storeVersionId == nil)
        #expect(tool.storeVersionNumber == nil)
        #expect(tool.storeSourceSha256 == nil)
        #expect(tool.storeImportedAt == nil)
        #expect(tool.storeRemixedFromVersionId == nil)
        #expect(tool.category == .utilities)
        #expect(!(models.contains { $0.id == modelID }))
    }

    @MainActor
    @Test
    func v2StoreMigratesToCurrentSchemaByDeletingLegacyLocalModels() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let storeURL = root.appendingPathComponent("anvil.sqlite")
        let config = ModelConfiguration(url: storeURL)
        let legacyModelID = UUID()
        let foundationModelID = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: AnvilSchemaV2.self),
                configurations: config
            )
            let context = ModelContext(container)
            let provider = AnvilSchemaV2.ProviderConfig(
                identifier: ProviderConfig.localProviderIdentifier,
                displayName: "Local",
                baseURLString: "",
                authMode: .none,
                origin: .builtIn
            )
            let legacyModel = AnvilSchemaV2.ModelConfig(
                id: legacyModelID,
                identifier: "legacy.local",
                displayName: "Legacy Local",
                providerIdentifier: provider.identifier,
                source: .mlx,
                installState: .installed
            )
            let foundationModel = AnvilSchemaV2.ModelConfig(
                id: foundationModelID,
                identifier: ModelConfig.appleFoundationIdentifier,
                displayName: "Apple Foundation Model",
                providerIdentifier: provider.identifier,
                source: .appleFoundation,
                installState: .builtIn
            )
            context.insert(provider)
            context.insert(legacyModel)
            context.insert(foundationModel)
            try context.save()
        }

        let container = try AnvilModelContainerFactory.make(configuration: config)
        let context = ModelContext(container)
        let models = try context.fetch(FetchDescriptor<ModelConfig>())

        #expect(container.schema.version == AnvilSchemaV7.versionIdentifier)
        #expect(!(models.contains { $0.id == legacyModelID }))
        #expect(models.contains { $0.id == foundationModelID })
    }

    @MainActor
    @Test
    func v3CustomProviderMigratesWithChatCompletionsDefault() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let config = ModelConfiguration(url: root.appendingPathComponent("anvil.sqlite"))
        let providerID = UUID()
        let modelID = UUID()

        do {
            let container = try ModelContainer(
                for: Schema(versionedSchema: AnvilSchemaV3.self),
                configurations: config
            )
            let context = ModelContext(container)
            context.insert(
                AnvilSchemaV3.ProviderConfig(
                    id: providerID,
                    identifier: "custom.test",
                    displayName: "Test Server",
                    baseURLString: "http://localhost:1234/v1",
                    authMode: .apiKey,
                    origin: .custom
                )
            )
            context.insert(
                AnvilSchemaV3.ModelConfig(
                    id: modelID,
                    identifier: "test-model",
                    displayName: "Test Model",
                    providerIdentifier: "custom.test",
                    source: .remote,
                    installState: .installed
                )
            )
            try context.save()
        }

        let container = try AnvilModelContainerFactory.make(configuration: config)
        let context = ModelContext(container)
        let provider = try #require(
            try context.fetch(FetchDescriptor<ProviderConfig>()).first { $0.id == providerID }
        )
        let model = try #require(
            try context.fetch(FetchDescriptor<ModelConfig>()).first { $0.id == modelID }
        )

        #expect(provider.openAICompatibleAPIVariant == .chatCompletions)
        #expect(model.reasoningEffortRawValues == nil)
    }

    @MainActor
    @Test
    func legacyStoreIsCopiedBackedUpAndReopenedWithoutDeletingSource() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyDirectoryURL = root.appendingPathComponent("legacy", isDirectory: true)
        try FileManager.default.createDirectory(at: legacyDirectoryURL, withIntermediateDirectories: true)
        let legacyStoreURL = legacyDirectoryURL.appendingPathComponent("default.store")

        do {
            let container = try ModelContainer(
                for: Tool.self,
                ModelConfig.self,
                ProviderConfig.self,
                configurations: ModelConfiguration(url: legacyStoreURL)
            )
            let context = ModelContext(container)
            context.insert(Tool(name: "Legacy Tool", packageRootPath: "/tmp/legacy-tool"))
            try context.save()
        }

        let locations = AnvilPersistentStoreLocations(
            databaseDirectoryURL: root
                .appendingPathComponent(".anvil", isDirectory: true)
                .appendingPathComponent("db", isDirectory: true),
            legacyStoreURL: legacyStoreURL
        )
        try AnvilPersistentStorePreparer(locations: locations)
            .prepare(startupDate: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
        #expect(FileManager.default.fileExists(atPath: locations.storeURL.path))

        let backupDirectoryURL = try #require(
            try Self.startupBackupDirectories(in: locations).first
        )
        let backupStoreURL = backupDirectoryURL.appendingPathComponent(AnvilPaths.databaseFileName)
        #expect(FileManager.default.fileExists(atPath: backupStoreURL.path))

        do {
            let container = try AnvilModelContainerFactory.make(
                configuration: ModelConfiguration(url: locations.storeURL)
            )
            let context = ModelContext(container)
            let tool = try #require(try context.fetch(FetchDescriptor<Tool>()).first)
            #expect(tool.name == "Legacy Tool")
        }

        do {
            let container = try AnvilModelContainerFactory.make(
                configuration: ModelConfiguration(url: backupStoreURL)
            )
            let context = ModelContext(container)
            let tool = try #require(try context.fetch(FetchDescriptor<Tool>()).first)
            #expect(tool.name == "Legacy Tool")
        }
    }

    @MainActor
    @Test
    func unrelatedDefaultStoreIsNotImportedAsLegacyAnvilData() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyStoreURL = root.appendingPathComponent("legacy/default.store")
        try FileManager.default.createDirectory(
            at: legacyStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.makeUnrelatedStore(at: legacyStoreURL)

        let locations = Self.makePersistentStoreLocations(
            root: root,
            legacyStoreURL: legacyStoreURL
        )
        try AnvilPersistentStorePreparer(locations: locations).prepare()

        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))
        #expect(!FileManager.default.fileExists(atPath: locations.storeURL.path))
    }

    @MainActor
    @Test
    func copiedUnrelatedLegacyStoreIsQuarantinedAndReplacedWithFreshStore() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyStoreURL = root.appendingPathComponent("legacy/default.store")
        try FileManager.default.createDirectory(
            at: legacyStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Self.makeUnrelatedStore(at: legacyStoreURL)

        let locations = Self.makePersistentStoreLocations(
            root: root,
            legacyStoreURL: legacyStoreURL
        )
        try FileManager.default.createDirectory(
            at: locations.databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        for suffix in ["", "-wal", "-shm"] {
            let sourceURL = URL(fileURLWithPath: legacyStoreURL.path + suffix)
            guard FileManager.default.fileExists(atPath: sourceURL.path) else { continue }
            try FileManager.default.copyItem(
                at: sourceURL,
                to: URL(fileURLWithPath: locations.storeURL.path + suffix)
            )
        }

        try AnvilPersistentStorePreparer(locations: locations)
            .prepare(startupDate: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(!FileManager.default.fileExists(atPath: locations.storeURL.path))
        let quarantines = try FileManager.default.contentsOfDirectory(
            at: locations.backupsDirectoryURL,
            includingPropertiesForKeys: nil
        ).filter { $0.lastPathComponent.hasPrefix("rejected-legacy-import-") }
        let quarantine = try #require(quarantines.first)
        #expect(FileManager.default.fileExists(
            atPath: quarantine.appendingPathComponent(AnvilPaths.databaseFileName).path
        ))
        #expect(FileManager.default.fileExists(atPath: legacyStoreURL.path))

        let container = try AnvilModelContainerFactory.make(
            configuration: ModelConfiguration(url: locations.storeURL)
        )
        let context = ModelContext(container)
        try AppDataBootstrapper.bootstrapIfNeeded(in: context)
        #expect(try context.fetch(FetchDescriptor<ProviderConfig>()).count == 1)
    }

    @Test
    func existingStoreIsBackedUpInsteadOfBeingReplacedByLegacyStore() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let legacyStoreURL = root.appendingPathComponent("legacy/default.store")
        try FileManager.default.createDirectory(
            at: legacyStoreURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("legacy".utf8).write(to: legacyStoreURL)

        let locations = AnvilPersistentStoreLocations(
            databaseDirectoryURL: root
                .appendingPathComponent(".anvil", isDirectory: true)
                .appendingPathComponent("db", isDirectory: true),
            legacyStoreURL: legacyStoreURL
        )
        try FileManager.default.createDirectory(
            at: locations.databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("current".utf8).write(to: locations.storeURL)

        try AnvilPersistentStorePreparer(locations: locations)
            .prepare(startupDate: Date(timeIntervalSince1970: 1_750_000_000))

        #expect(try Data(contentsOf: locations.storeURL) == Data("current".utf8))
        #expect(try Data(contentsOf: legacyStoreURL) == Data("legacy".utf8))

        let backupDirectoryURL = try #require(
            try Self.startupBackupDirectories(in: locations).first
        )
        let backupStoreURL = backupDirectoryURL.appendingPathComponent(AnvilPaths.databaseFileName)
        #expect(try Data(contentsOf: backupStoreURL) == Data("current".utf8))
    }

    @Test
    func startupBackupsRetainOnlyTheThreeNewestSnapshots() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }

        let locations = AnvilPersistentStoreLocations(
            databaseDirectoryURL: root
                .appendingPathComponent(".anvil", isDirectory: true)
                .appendingPathComponent("db", isDirectory: true),
            legacyStoreURL: root.appendingPathComponent("legacy/default.store")
        )
        try FileManager.default.createDirectory(
            at: locations.databaseDirectoryURL,
            withIntermediateDirectories: true
        )
        try Data("current".utf8).write(to: locations.storeURL)

        let preparer = AnvilPersistentStorePreparer(locations: locations)
        for offset in 0..<5 {
            try preparer.prepare(
                startupDate: Date(timeIntervalSince1970: 1_750_000_000 + Double(offset))
            )
        }

        let backupNames = try Self.startupBackupDirectories(in: locations)
            .map(\.lastPathComponent)
            .sorted()

        #expect(backupNames == [
            "20250615-150642-000",
            "20250615-150643-000",
            "20250615-150644-000",
        ])
    }

    @Test
    func persistentStorePathUsesAnvilDatabaseDirectory() {
        let expectedDirectory = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".anvil/db", isDirectory: true)

        #expect(AnvilPaths.databaseDirectory == expectedDirectory)
        #expect(
            AnvilPaths.databaseURL
                == expectedDirectory.appendingPathComponent(AnvilPaths.databaseFileName)
        )
        #expect(
            AnvilPaths.databaseBackupsDirectory
                == expectedDirectory.appendingPathComponent("backups", isDirectory: true)
        )
    }

    @Test
    func generatedBundleIdentifiersUseASCIISafeComponents() throws {
        let id = try #require(UUID(uuidString: "11111111-2222-3333-4444-555555555555"))
        let bundleIdentifier = ToolBundleIdentifier.make(executableName: "Résumé Helper 東京", id: id)
        let allowedCharacters = Set("abcdefghijklmnopqrstuvwxyz0123456789-.")

        #expect(bundleIdentifier == "com.anvil.generated.resume-helper.11111111-2222-3333-4444-555555555555")
        #expect(bundleIdentifier.allSatisfy { allowedCharacters.contains($0) })
    }

    @Test
    func welcomeOnboardingStoreDefaultsToIncomplete() {
        let store = Self.makeWelcomeOnboardingStore()

        #expect(!store.hasCompleted)
    }

    @Test
    func welcomeOnboardingStorePersistsCompletionAcrossInstances() {
        let suiteName = "AnvilTests.WelcomeOnboarding.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)

        let firstStore = WelcomeOnboardingStore(userDefaults: userDefaults)
        firstStore.complete()
        let secondStore = WelcomeOnboardingStore(userDefaults: userDefaults)

        #expect(secondStore.hasCompleted)
    }

    @Test
    func legacyIronsmithDataDirectoryMigratesToAnvil() throws {
        let root = try Self.makeTemporaryDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let legacyRoot = root.appendingPathComponent(".ironsmith", isDirectory: true)
        let currentRoot = root.appendingPathComponent(".anvil", isDirectory: true)
        let legacyDatabaseDirectory = legacyRoot.appendingPathComponent("db", isDirectory: true)
        try FileManager.default.createDirectory(
            at: legacyDatabaseDirectory,
            withIntermediateDirectories: true
        )
        try "data".write(
            to: legacyDatabaseDirectory.appendingPathComponent("ironsmith.sqlite"),
            atomically: true,
            encoding: .utf8
        )
        try "wal".write(
            to: legacyDatabaseDirectory.appendingPathComponent("ironsmith.sqlite-wal"),
            atomically: true,
            encoding: .utf8
        )

        try AnvilPaths.migrateLegacyDataIfNeeded(legacyRoot: legacyRoot, currentRoot: currentRoot)

        #expect(!FileManager.default.fileExists(atPath: legacyRoot.path))
        let migratedDatabaseDirectory = currentRoot.appendingPathComponent("db", isDirectory: true)
        #expect(FileManager.default.fileExists(
            atPath: migratedDatabaseDirectory.appendingPathComponent("anvil.sqlite").path
        ))
        #expect(FileManager.default.fileExists(
            atPath: migratedDatabaseDirectory.appendingPathComponent("anvil.sqlite-wal").path
        ))

        // A second run is a no-op.
        try AnvilPaths.migrateLegacyDataIfNeeded(legacyRoot: legacyRoot, currentRoot: currentRoot)
        #expect(FileManager.default.fileExists(
            atPath: migratedDatabaseDirectory.appendingPathComponent("anvil.sqlite").path
        ))
    }

    private static func makeWelcomeOnboardingStore() -> WelcomeOnboardingStore {
        let suiteName = "AnvilTests.WelcomeOnboarding.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return WelcomeOnboardingStore(userDefaults: userDefaults)
    }

    private static func makeTemporaryDirectory() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-persistence-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func makePersistentStoreLocations(
        root: URL,
        legacyStoreURL: URL
    ) -> AnvilPersistentStoreLocations {
        AnvilPersistentStoreLocations(
            databaseDirectoryURL: root
                .appendingPathComponent(".anvil", isDirectory: true)
                .appendingPathComponent("db", isDirectory: true),
            legacyStoreURL: legacyStoreURL
        )
    }

    @MainActor
    private static func makeUnrelatedStore(at url: URL) throws {
        let container = try ModelContainer(
            for: UnrelatedLegacyRecord.self,
            configurations: ModelConfiguration(url: url)
        )
        let context = ModelContext(container)
        context.insert(UnrelatedLegacyRecord(value: "Not Anvil"))
        try context.save()
    }

    private static func startupBackupDirectories(
        in locations: AnvilPersistentStoreLocations
    ) throws -> [URL] {
        try FileManager.default.contentsOfDirectory(
            at: locations.backupsDirectoryURL,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
    }
}

@Model
private final class UnrelatedLegacyRecord {
    var value: String

    init(value: String) {
        self.value = value
    }
}
