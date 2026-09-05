import AnyLanguageModel
import Foundation
import SwiftData
import Testing
@testable import Anvil

struct InferenceTests {}

extension InferenceTests {
    @MainActor
    static func dependenciesBackedStore(
        generationPreferences: GenerationPreferencesStore? = nil
    ) -> InferenceStore {
        InferenceStore(
            dependencies: Self.dependencies(),
            generationPreferences: generationPreferences,
            appleFoundationModelPreferenceStore: Self.appleFoundationModelPreferenceStore()
        )
    }

    @MainActor
    static func agentLanguageModelContext(
        providerKind: ProviderKind
    ) async throws -> AgentLanguageModelContext {
        let preferences = Self.generationPreferences()
        preferences.codingAgentPreference = .anvilFlame
        let store = Self.dependenciesBackedStore(generationPreferences: preferences)
        let provider = ProviderCatalog.makeProvider(for: providerKind)!
        let model = ModelConfig(
            identifier: "\(providerKind.rawValue)-test",
            displayName: "Test Model",
            providerIdentifier: provider.identifier,
            source: .remote,
            installState: .installed
        )

        store.providers = [provider]
        store.remoteModels = [model]
        store.selectedModelID = model.selectionIdentifier

        return try await store.makeSelectedAgentLanguageModelContext()
    }

    @MainActor
    static func generationPreferences() -> GenerationPreferencesStore {
        let suiteName = "AnvilTests.GenerationPreferences.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return GenerationPreferencesStore(userDefaults: userDefaults)
    }

    @MainActor
    static func modelSelection() -> ModelSelectionStore {
        let suiteName = "AnvilTests.ModelSelection.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        return ModelSelectionStore(userDefaults: userDefaults)
    }

    static func appleFoundationModelPreferenceStore(
        isEnabled: Bool = false
    ) -> AppleFoundationModelPreferenceStore {
        let suiteName = "AnvilTests.AppleFoundation.\(UUID().uuidString)"
        let userDefaults = UserDefaults(suiteName: suiteName)!
        userDefaults.removePersistentDomain(forName: suiteName)
        let store = AppleFoundationModelPreferenceStore(userDefaults: userDefaults)
        store.isEnabled = isEnabled
        return store
    }

    static func dependencies(
        remoteModelIDs: [String] = [],
        remoteDiscoveryHook: (() async -> Void)? = nil,
        remoteDiscoveryScript: RemoteDiscoveryScript? = nil,
        downloadResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/model")),
        remoteDiscoveryError: Error? = nil,
        ollamaInstalled: Bool = false,
        ollamaStartResult: Result<Void, Error> = .success(()),
        ollamaPullProgresses: [OllamaPullProgress] = [],
        ollamaPullResult: Result<Void, Error> = .success(()),
        ollamaDeleteResult: Result<Void, Error> = .success(()),
        openAICodexAuthClient: OpenAICodexAuthClient = .unconfigured
    ) -> InferenceDependencies {
        let credentialBox = CredentialBox()
        return InferenceDependencies(
            credentialClient: CredentialClient(
                loadAPIKey: { reference in
                    credentialBox.values[reference]
                },
                saveAPIKey: { apiKey, reference in
                    credentialBox.values[reference] = apiKey
                },
                deleteAPIKey: { reference in
                    credentialBox.values.removeValue(forKey: reference)
                }
            ),
            openAICodexAuthClient: openAICodexAuthClient,
            remoteModelClient: RemoteModelClient { provider, _ in
                await remoteDiscoveryHook?()
                if let remoteDiscoveryScript {
                    let identifiers = try await remoteDiscoveryScript.identifiers()
                    return identifiers.map {
                        ModelConfig(
                            identifier: $0,
                            displayName: $0,
                            providerIdentifier: provider.identifier,
                            source: .remote,
                            installState: .installed
                        )
                    }
                }
                if let remoteDiscoveryError {
                    throw remoteDiscoveryError
                }
                return remoteModelIDs.map {
                    ModelConfig(
                        identifier: $0,
                        displayName: $0,
                        providerIdentifier: provider.identifier,
                        source: .remote,
                        installState: .installed
                    )
                }
            },
            localModelClient: fakeLocalModelClient(downloadResult: downloadResult),
            ollamaClient: OllamaClient(
                isInstalled: {
                    ollamaInstalled
                },
                startServer: {
                    try ollamaStartResult.get()
                },
                pullModel: { _, _, _, progress in
                    for update in ollamaPullProgresses {
                        await progress(update)
                    }
                    try ollamaPullResult.get()
                },
                deleteModel: { _, _, _ in
                    try ollamaDeleteResult.get()
                }
            ),
            languageModelClient: LanguageModelClient(
                makeLanguageModel: { _, _ in
                    InferenceTestLanguageModel()
                }
            )
        )
    }

    static func fakeLocalModelClient(
        downloadResult: Result<URL, Error> = .success(URL(fileURLWithPath: "/tmp/model"))
    ) -> LocalModelClient {
        LocalModelClient(
            makeHubAPI: {
                fatalError("makeHubAPI should not be used by these tests")
            },
            downloadModel: { _, progress in
                progress(0.25)
                progress(1)
                return try downloadResult.get()
            },
            deleteModel: { _ in }
        )
    }

    @MainActor
    static func eventually(
        timeoutNanoseconds: UInt64 = 5_000_000_000,
        _ predicate: @escaping @MainActor () -> Bool
    ) async {
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        while DispatchTime.now().uptimeNanoseconds < deadline {
            if predicate() { return }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }
    }
}

final class CredentialBox {
    var values: [String: String] = [:]
}

actor RemoteDiscoveryCounter {
    private var value = 0

    var count: Int {
        value
    }

    func increment() {
        value += 1
    }
}

actor RemoteDiscoveryGate {
    private var isOpen = false
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        guard !isOpen else { return }
        await withCheckedContinuation {
            continuation = $0
        }
    }

    func open() {
        isOpen = true
        continuation?.resume()
        continuation = nil
    }
}

actor RemoteDiscoveryScript {
    private var results: [Result<[String], Error>]
    private var requestCount = 0

    init(_ results: [Result<[String], Error>]) {
        self.results = results
    }

    var count: Int {
        requestCount
    }

    func identifiers() throws -> [String] {
        requestCount += 1
        let result = results.isEmpty ? .success([]) : results.removeFirst()
        return try result.get()
    }
}

struct InferenceTestLanguageModel: LanguageModel {
    typealias UnavailableReason = Never

    func respond<Content>(
        within session: LanguageModelSession,
        to prompt: Prompt,
        generating type: Content.Type,
        includeSchemaInPrompt: Bool,
        options: GenerationOptions
    ) async throws -> LanguageModelSession.Response<Content> where Content: Generable {
        throw FakeInferenceError.expected
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
                continuation.finish(throwing: FakeInferenceError.expected)
            }
        )
    }
}

enum FakeInferenceError: LocalizedError {
    case expected
    case unexpectedNonStreamingRetry

    var errorDescription: String? {
        switch self {
        case .expected:
            "Expected test failure."
        case .unexpectedNonStreamingRetry:
            "Non-streaming respond should not have been called."
        }
    }
}
