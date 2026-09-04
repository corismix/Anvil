import AnyLanguageModel
import Foundation
import SwiftData
import Testing
@testable import Anvil

struct ToolLibraryTests {}

extension ToolLibraryTests {
    static func inferenceDependencies() -> InferenceDependencies {
        InferenceDependencies(
            credentialClient: CredentialClient(
                loadAPIKey: { _ in nil },
                saveAPIKey: { _, _ in },
                deleteAPIKey: { _ in }
            ),
            remoteModelClient: RemoteModelClient { _, _ in [] },
            localModelClient: LocalModelClient(
                makeHubAPI: {
                    fatalError("makeHubAPI should not be used by these tests")
                },
                downloadModel: { _, _ in URL(fileURLWithPath: "/tmp/model", isDirectory: true) },
                deleteModel: { _ in }
            ),
            ollamaClient: .noOp(),
            languageModelClient: LanguageModelClient(
                makeLanguageModel: { _, _ in ToolLibraryTestLanguageModel() }
            )
        )
    }

    static func makeTemporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-tool-library-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    static func makeIsolatedUserDefaults() throws -> UserDefaults {
        let suiteName = "anvil-tool-library-tests-\(UUID().uuidString)"
        let userDefaults = try #require(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        return userDefaults
    }

    static func appleFoundationModelPreferenceStore(
        isEnabled: Bool = true
    ) throws -> AppleFoundationModelPreferenceStore {
        let store = AppleFoundationModelPreferenceStore(userDefaults: try makeIsolatedUserDefaults())
        store.isEnabled = isEnabled
        return store
    }

    static func remoteModel(
        provider: ProviderConfig,
        identifier: String = "test/model",
        estimatedToolCredits: Int?
    ) -> ModelConfig {
        ModelConfig(
            identifier: identifier,
            displayName: "Test Model",
            providerIdentifier: provider.identifier,
            source: .remote,
            installState: .installed,
            estimatedToolCredits: estimatedToolCredits
        )
    }
}

enum AppUpdateFetchError: Error {
    case failed
}

actor AppUpdateFetchCapture {
    private let result: Result<AppUpdateRelease, Error>
    private(set) var fetchCount = 0

    init(result: Result<AppUpdateRelease, Error>) {
        self.result = result
    }

    func fetch() throws -> AppUpdateRelease {
        fetchCount += 1
        return try result.get()
    }
}


actor ToolBuildCapture {
    private(set) var builtPackageRoot: URL?
    private(set) var builtSettings: ToolGenerationSettings?

    func record(_ url: URL) {
        builtPackageRoot = url
    }

    func record(_ tool: Anvil.Tool) {
        builtPackageRoot = tool.packageRootURL
        builtSettings = tool.generationSettings(defaults: .default)
    }
}

actor ToolExportCapture {
    private(set) var exportedToolID: UUID?

    func record(_ tool: Anvil.Tool) {
        exportedToolID = tool.id
    }
}

actor ToolRunningCapture {
    private(set) var launchedToolIDs: [UUID] = []
    private(set) var quitToolIDs: [UUID] = []
    private var runningToolIDs = Set<UUID>()

    func recordLaunch(_ tool: StoredTool) {
        launchedToolIDs.append(tool.id)
        runningToolIDs.insert(tool.id)
    }

    func recordQuit(_ tool: StoredTool) {
        quitToolIDs.append(tool.id)
        runningToolIDs.remove(tool.id)
    }

    func isRunning(_ tool: StoredTool) -> Bool {
        runningToolIDs.contains(tool.id)
    }
}

actor ToolFinderCapture {
    private(set) var openedURL: URL?

    func record(_ url: URL) {
        openedURL = url
    }
}

struct ToolLibraryTestLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        throw ToolLibraryTestLanguageModelError.unused
    }

    func streamResponse<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) -> sending LanguageModelSession.ResponseStream<Content> where Content: Generable {
        LanguageModelSession.ResponseStream(
            stream: AsyncThrowingStream { continuation in
                continuation.finish(throwing: ToolLibraryTestLanguageModelError.unused)
            }
        )
    }
}

enum ToolLibraryTestLanguageModelError: Error {
    case unused
}
