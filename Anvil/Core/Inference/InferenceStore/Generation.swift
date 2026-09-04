import Foundation

extension InferenceStore {
    func makeSelectedAgentLanguageModelContext(
        resolutionContext: ToolCodingAgentResolutionContext = .create
    ) async throws -> AgentLanguageModelContext {
        guard let selectedModel else {
            throw InferenceStoreError.missingSelectedModel
        }

        let provider = provider(for: selectedModel)
        let languageModel = try await dependencies.languageModelClient.makeLanguageModel(
            selectedModel, provider)
        let codingAgent = ToolCodingAgentResolver.resolve(
            requested: generationPreferences.codingAgentPreference,
            model: selectedModel,
            provider: provider,
            context: resolutionContext
        )
        let reasoningEffort = ToolReasoningSupport.effectiveEffort(
            requested: generationPreferences.reasoningEffort,
            model: selectedModel,
            provider: provider
        )
        let customCodingAgent: CustomCodingAgent?
        if codingAgent == .custom {
            guard let selectedAgent = customCodingAgents.selectedAgent else {
                throw InferenceStoreError.missingCustomCodingAgent
            }
            customCodingAgent = selectedAgent
        } else {
            customCodingAgent = nil
        }
        return AgentLanguageModelContext(
            codingAgent: ToolGenerationOptionsResolver.stageConfiguration(
                for: .codingAgent,
                model: selectedModel,
                provider: provider,
                languageModel: languageModel,
                reasoningEffort: reasoningEffort
            ),
            promptRefinement: ToolGenerationOptionsResolver.stageConfiguration(
                for: .promptRefinement,
                model: selectedModel,
                provider: provider,
                languageModel: languageModel,
                reasoningEffort: reasoningEffort
            ),
            metadata: ToolGenerationOptionsResolver.stageConfiguration(
                for: .metadata,
                model: selectedModel,
                provider: provider,
                languageModel: languageModel,
                reasoningEffort: reasoningEffort
            ),
            pipelineConfiguration: pipelineConfiguration(for: selectedModel, codingAgent: codingAgent),
            promptRefinementEnabled: generationPreferences.generatedPromptRefinementEnabled,
            codingAgentModelIdentifier: selectedModel.identifier,
            codingAgentModelFamily: ToolModelFamily.resolved(
                model: selectedModel,
                provider: provider
            ),
            codingAgentContextWindowTokens: nil,
            codexAgentAuthentication: try await codexAgentAuthentication(
                for: selectedModel,
                provider: provider,
                codingAgent: codingAgent
            ),
            customCodingAgent: customCodingAgent,
            codingAgentSupportsImageInput: ToolAttachmentSupport.isSupported(
                model: selectedModel,
                provider: provider,
                codingAgent: codingAgent
            ),
            reasoningEffort: reasoningEffort
        )
    }

    func selectedModelSupportsAttachments(
        resolutionContext: ToolCodingAgentResolutionContext = .create
    ) -> Bool {
        guard let selectedModel else { return false }
        let provider = provider(for: selectedModel)
        let codingAgent = ToolCodingAgentResolver.resolve(
            requested: generationPreferences.codingAgentPreference,
            model: selectedModel,
            provider: provider,
            context: resolutionContext
        )
        return ToolAttachmentSupport.isSupported(
            model: selectedModel,
            provider: provider,
            codingAgent: codingAgent
        )
    }

    func selectedModelCanUseCodexAttachments() -> Bool {
        guard let selectedModel else { return false }
        return ToolAttachmentSupport.canUseCodexAttachments(
            model: selectedModel,
            provider: provider(for: selectedModel)
        )
    }

    func selectedModelUsesCodex(
        resolutionContext: ToolCodingAgentResolutionContext = .create
    ) -> Bool {
        guard let selectedModel else { return false }
        return ToolCodingAgentResolver.resolve(
            requested: generationPreferences.codingAgentPreference,
            model: selectedModel,
            provider: provider(for: selectedModel),
            context: resolutionContext
        ) == .codex
    }

    func prepareSelectedModelForGeneration() async throws {
        guard selectedModel != nil else {
            throw InferenceStoreError.missingSelectedModel
        }
    }

    private func pipelineConfiguration(
        for model: ModelConfig,
        codingAgent: ToolCodingAgent
    ) -> ToolGenerationPipelineConfiguration {
        switch codingAgent {
        case .anvilSpark:
            return .anvilSpark(repairStrategy: smallModelRepairStrategy(for: model))
        case .anvilFlame:
            return .anvilFlame(
                repairStrategy: .modelSearchReplace(
                    maxPatchBlocksPerTurn: ToolGenerationRepairPolicy.largeModelPatchBlocksPerTurn
                )
            )
        case .codex:
            return .codex()
        case .custom:
            return .custom()
        }
    }

    private func codexAgentAuthentication(
        for model: ModelConfig,
        provider: ProviderConfig?,
        codingAgent: ToolCodingAgent
    ) async throws -> CodexAgentAuthentication? {
        guard codingAgent == .codex else {
            return nil
        }
        guard let provider else {
            throw CodexAgentError.unsupportedProvider
        }

        switch provider.kind {
        case .openAI:
            if model.openAICodexRawIdentifier != nil {
                return .chatGPTLogin
            }
            guard let reference = provider.apiKeyReference,
                  let apiKey = try dependencies.credentialClient.loadAPIKey(reference),
                  !apiKey.isEmpty
            else {
                throw LanguageModelClientError.missingAPIKey
            }
            return .apiKey(apiKey)
        case .ollama:
            return .customResponsesProvider(
                try codexCustomResponsesProvider(
                    provider,
                    configurationIdentifier: "anvil_ollama",
                    baseURL: codexOllamaBaseURL(provider)
                )
            )
        case .customOpenAICompatible:
            guard provider.openAICompatibleAPIVariant == .responses else {
                throw CodexAgentError.unsupportedProvider
            }
            return .customResponsesProvider(
                try codexCustomResponsesProvider(
                    provider,
                    configurationIdentifier: "anvil_custom_\(provider.id.uuidString.replacingOccurrences(of: "-", with: "").lowercased())",
                    baseURL: codexProviderBaseURL(provider)
                )
            )
        case .local, .anthropic, .gemini, .anvil:
            throw CodexAgentError.unsupportedProvider
        }
    }

    private func codexCustomResponsesProvider(
        _ provider: ProviderConfig,
        configurationIdentifier: String,
        baseURL: URL
    ) throws -> CodexAgentCustomResponsesProvider {
        let apiKey: String? = if let reference = provider.apiKeyReference {
            try dependencies.credentialClient.loadAPIKey(reference)
        } else {
            nil
        }
        let trimmedAPIKey = apiKey?.trimmingCharacters(in: .whitespacesAndNewlines)
        let hasAPIKey = trimmedAPIKey?.isEmpty == false
        return CodexAgentCustomResponsesProvider(
            configurationIdentifier: configurationIdentifier,
            sessionProviderIdentifier: provider.identifier,
            displayName: provider.displayName,
            baseURL: baseURL,
            authenticationEnvironmentVariable: hasAPIKey
                ? "ANVIL_CODEX_PROVIDER_API_KEY"
                : nil,
            authenticationToken: hasAPIKey ? trimmedAPIKey : nil
        )
    }

    private func codexOllamaBaseURL(_ provider: ProviderConfig) throws -> URL {
        let baseURL = try codexProviderBaseURL(provider)
        if baseURL.pathComponents.last?.lowercased() == "v1" {
            return baseURL
        }
        return baseURL.appendingPathComponent("v1", isDirectory: true)
    }

    private func codexProviderBaseURL(_ provider: ProviderConfig) throws -> URL {
        let descriptor = ProviderCatalog.descriptor(for: provider.kind)
        let baseURLString = provider.baseURLString.isEmpty
            ? descriptor?.defaultBaseURLString ?? ""
            : provider.baseURLString
        guard let baseURL = try? ProviderBaseURLValidator.validatedURL(from: baseURLString) else {
            throw LanguageModelClientError.invalidProviderURL
        }
        return baseURL
    }

    private func smallModelRepairStrategy(for model: ModelConfig) -> ToolRepairStrategy {
        switch model.source {
        case .appleFoundation:
            return .deterministicOnly
        case .mlx:
            return .deterministicOnly
        case .remote:
            return .modelSearchReplace(
                maxPatchBlocksPerTurn: ToolGenerationRepairPolicy.smallModelPatchBlocksPerTurn
            )
        }
    }
}
