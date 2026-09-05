import AnyLanguageModel
import Foundation
import Testing
@testable import Anvil

struct OpenCodeZenCatalogTests {
    private let zenBaseURL = URL(string: "https://opencode.ai/zen/v1")!
    private let goBaseURL = URL(string: "https://opencode.ai/zen/go/v1")!

    // MARK: - Endpoint detection

    @Test
    func detectsZenAndGoTiers() {
        #expect(OpenCodeZenCatalog.tier(for: zenBaseURL) == .zen)
        #expect(OpenCodeZenCatalog.tier(for: goBaseURL) == .go)
        #expect(
            OpenCodeZenCatalog.tier(for: URL(string: "https://opencode.ai/zen/go/v1/")!) == .go
        )
    }

    @Test
    func rejectsNonZenEndpoints() {
        #expect(OpenCodeZenCatalog.tier(for: URL(string: "https://api.openai.com/v1")!) == nil)
        #expect(OpenCodeZenCatalog.tier(for: URL(string: "https://opencode.ai/auth")!) == nil)
        #expect(OpenCodeZenCatalog.tier(for: URL(string: "https://opencode.ai.evil.com/zen/v1")!) == nil)
        #expect(OpenCodeZenCatalog.tier(for: URL(string: "http://localhost:1234/v1")!) == nil)
        #expect(OpenCodeZenCatalog.isZenEndpoint(zenBaseURL))
        #expect(!OpenCodeZenCatalog.isZenEndpoint(URL(string: "https://api.anthropic.com")!))
    }

    // MARK: - Seeded tables

    @Test
    func seededGoFormatsMatchOfficialTable() {
        let cases: [(String, OpenCodeZenAPIFormat)] = [
            ("grok-4.6", .responses),
            ("gpt-5.6-luna", .responses),
            ("muse-spark-1.3-contributor", .responses),
            ("muse-spark-1.2-contributor", .responses),
            ("minimax-m3", .anthropicMessages),
            ("minimax-m2.7", .anthropicMessages),
            ("minimax-m2.5", .anthropicMessages),
            ("qwen3.8-max", .anthropicMessages),
            ("qwen3.7-max", .anthropicMessages),
            ("qwen3.7-plus", .anthropicMessages),
            ("qwen3.6-plus", .anthropicMessages),
            ("glm-5.2", .chatCompletions),
            ("glm-5.3-flash", .chatCompletions),
            ("kimi-k3", .chatCompletions),
            ("kimi-k2.6", .chatCompletions),
            ("deepseek-v4-pro", .chatCompletions),
            ("deepseek-v4-flash", .chatCompletions),
            ("mimo-v2.5", .chatCompletions),
            ("longcat-2.0", .chatCompletions),
            ("hy3", .chatCompletions),
            ("omen-alpha", .chatCompletions),
        ]
        for (model, expected) in cases {
            #expect(
                OpenCodeZenCatalog.apiFormat(forModelIdentifier: model, baseURL: goBaseURL)
                    == expected,
                "go model \(model)"
            )
        }
    }

    @Test
    func seededZenFormatsMatchOfficialTable() {
        let cases: [(String, OpenCodeZenAPIFormat)] = [
            ("gpt-5.5", .responses),
            ("gpt-5.1-codex-max", .responses),
            ("grok-4.5", .responses),
            ("muse-spark-1.3", .responses),
            ("claude-opus-5", .anthropicMessages),
            ("claude-sonnet-4-6", .anthropicMessages),
            ("claude-haiku-4-5", .anthropicMessages),
            ("qwen3.7-max", .anthropicMessages),
            ("qwen3.5-plus", .anthropicMessages),
            ("minimax-m2.7", .chatCompletions),
            ("glm-5.2", .chatCompletions),
            ("kimi-k2.7-code", .chatCompletions),
            ("deepseek-v4-flash", .chatCompletions),
            ("big-pickle", .chatCompletions),
        ]
        for (model, expected) in cases {
            #expect(
                OpenCodeZenCatalog.apiFormat(forModelIdentifier: model, baseURL: zenBaseURL)
                    == expected,
                "zen model \(model)"
            )
        }
    }

    @Test
    func minimaxFormatDiffersBetweenTiers() {
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "minimax-m2.7", baseURL: goBaseURL)
                == .anthropicMessages
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "minimax-m2.7", baseURL: zenBaseURL)
                == .chatCompletions
        )
    }

    // MARK: - Fallbacks

    @Test
    func unknownModelsFallBackByFamilyPrefix() {
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "gpt-7-ultra", baseURL: zenBaseURL)
                == .responses
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "grok-9", baseURL: goBaseURL)
                == .responses
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "claude-opus-9", baseURL: zenBaseURL)
                == .anthropicMessages
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "qwen4-max", baseURL: goBaseURL)
                == .anthropicMessages
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "minimax-m4", baseURL: goBaseURL)
                == .anthropicMessages
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "minimax-m4", baseURL: zenBaseURL)
                == .chatCompletions
        )
        #expect(
            OpenCodeZenCatalog.apiFormat(forModelIdentifier: "some-future-model", baseURL: goBaseURL)
                == .chatCompletions
        )
    }

    @Test
    func nonZenEndpointsHaveNoAutomaticFormat() {
        #expect(
            OpenCodeZenCatalog.apiFormat(
                forModelIdentifier: "glm-5.2",
                baseURL: URL(string: "http://localhost:1234/v1")!
            ) == nil
        )
    }

    // MARK: - Anthropic base URL

    @Test
    func anthropicBaseURLStripsTrailingV1() {
        #expect(
            OpenCodeZenCatalog.anthropicBaseURL(for: goBaseURL).absoluteString
                == "https://opencode.ai/zen/go/"
        )
        #expect(
            OpenCodeZenCatalog.anthropicBaseURL(for: zenBaseURL).absoluteString
                == "https://opencode.ai/zen/"
        )
    }
}

struct OpenCodeZenRoutingTests {
    @MainActor
    private func makeClient() -> LanguageModelClient {
        LanguageModelClient.live(
            credentialClient: CredentialClient(
                loadAPIKey: { _ in "zen-key" },
                saveAPIKey: { _, _ in },
                deleteAPIKey: { _ in }
            ),
            localModelClient: InferenceTests.fakeLocalModelClient()
        )
    }

    @MainActor
    private func makeProviderAndModel(
        baseURLString: String,
        modelIdentifier: String
    ) -> (ProviderConfig, ModelConfig) {
        let provider = ProviderCatalog.makeProvider(for: .customOpenAICompatible)!
        provider.identifier = "custom.zen-test"
        provider.baseURLString = baseURLString
        let model = ModelConfig(
            identifier: modelIdentifier,
            displayName: modelIdentifier,
            providerIdentifier: provider.identifier,
            source: .remote,
            installState: .installed
        )
        return (provider, model)
    }

    @MainActor
    @Test
    func zenChatCompletionsModelUsesChatCompletionsVariant() async throws {
        let (provider, model) = makeProviderAndModel(
            baseURLString: "https://opencode.ai/zen/go/v1",
            modelIdentifier: "glm-5.2"
        )
        let languageModel = try await makeClient().makeLanguageModel(model, provider)
        let openAIModel = try #require(languageModel as? OpenAILanguageModel)
        #expect(openAIModel.apiVariant == .chatCompletions)
        #expect(openAIModel.model == "glm-5.2")
    }

    @MainActor
    @Test
    func zenResponsesOnlyModelUsesResponsesVariant() async throws {
        let (provider, model) = makeProviderAndModel(
            baseURLString: "https://opencode.ai/zen/go/v1",
            modelIdentifier: "grok-4.6"
        )
        provider.openAICompatibleAPIVariant = .chatCompletions
        let languageModel = try await makeClient().makeLanguageModel(model, provider)
        let openAIModel = try #require(languageModel as? OpenAILanguageModel)
        #expect(openAIModel.apiVariant == .responses)
    }

    @MainActor
    @Test
    func zenAnthropicFormatModelUsesAnthropicLanguageModel() async throws {
        let (provider, model) = makeProviderAndModel(
            baseURLString: "https://opencode.ai/zen/go/v1",
            modelIdentifier: "qwen3.7-max"
        )
        let languageModel = try await makeClient().makeLanguageModel(model, provider)
        let anthropicModel = try #require(languageModel as? AnthropicLanguageModel)
        #expect(anthropicModel.model == "qwen3.7-max")
        #expect(anthropicModel.baseURL.absoluteString == "https://opencode.ai/zen/go/")
    }

    @MainActor
    @Test
    func nonZenCustomProviderKeepsManualVariant() async throws {
        let (provider, model) = makeProviderAndModel(
            baseURLString: "http://localhost:1234/v1",
            modelIdentifier: "qwen3.7-max"
        )
        provider.openAICompatibleAPIVariant = .responses
        let languageModel = try await makeClient().makeLanguageModel(model, provider)
        let openAIModel = try #require(languageModel as? OpenAILanguageModel)
        #expect(openAIModel.apiVariant == .responses)
    }
}
