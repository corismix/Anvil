import Foundation

/// The API protocol one OpenCode Zen model speaks.
///
/// Zen serves its catalog over three different protocols depending on the
/// model family, so a single provider-wide API setting cannot be right for
/// every model.
nonisolated enum OpenCodeZenAPIFormat: String, Sendable, CaseIterable {
    case chatCompletions
    case responses
    case anthropicMessages

    var badgeLabel: String {
        switch self {
        case .chatCompletions:
            return "Chat Completions"
        case .responses:
            return "Responses"
        case .anthropicMessages:
            return "Messages"
        }
    }
}

/// Per-model API protocol knowledge for OpenCode Zen endpoints
/// (opencode.ai/zen/...), seeded from the official endpoint tables and
/// extended with family-prefix fallbacks for models the tables don't know
/// yet.
nonisolated enum OpenCodeZenCatalog {
    enum Tier: Sendable {
        /// Pay-per-use tier, base URL https://opencode.ai/zen/v1
        case zen
        /// Subscription tier, base URL https://opencode.ai/zen/go/v1
        case go
    }

    /// Returns the Zen tier when `baseURL` points at an OpenCode Zen
    /// endpoint, nil for any other host or path.
    static func tier(for baseURL: URL) -> Tier? {
        guard baseURL.host(percentEncoded: false)?.lowercased() == "opencode.ai" else {
            return nil
        }
        let components = baseURL.pathComponents.filter { $0 != "/" }
        guard components.first?.lowercased() == "zen" else {
            return nil
        }
        if components.count > 1, components[1].lowercased() == "go" {
            return .go
        }
        return .zen
    }

    static func isZenEndpoint(_ baseURL: URL) -> Bool {
        tier(for: baseURL) != nil
    }

    /// The protocol to use for a model served by a Zen endpoint, or nil when
    /// `baseURL` is not a Zen endpoint. Unknown models fall back to family
    /// prefixes and finally to chat completions, the most common format.
    static func apiFormat(
        forModelIdentifier identifier: String,
        baseURL: URL
    ) -> OpenCodeZenAPIFormat? {
        guard let tier = tier(for: baseURL) else {
            return nil
        }
        let id = identifier.lowercased()
        if let seeded = seededFormats(for: tier)[id] {
            return seeded
        }
        return fallbackFormat(forModelIdentifier: id, tier: tier)
    }

    /// The base URL to hand to AnthropicLanguageModel for a Zen endpoint.
    /// AnthropicLanguageModel appends "v1/messages" itself, and Zen's
    /// Anthropic-format root is the endpoint without its trailing "/v1".
    static func anthropicBaseURL(for baseURL: URL) -> URL {
        var url = baseURL
        if url.lastPathComponent.lowercased() == "v1" {
            url.deleteLastPathComponent()
        }
        return url
    }

    private static func fallbackFormat(
        forModelIdentifier id: String,
        tier: Tier
    ) -> OpenCodeZenAPIFormat {
        if id.hasPrefix("gpt-") || id.hasPrefix("grok") || id.hasPrefix("muse-spark") {
            return .responses
        }
        if id.hasPrefix("claude") || id.hasPrefix("qwen") {
            return .anthropicMessages
        }
        if id.hasPrefix("minimax") {
            return tier == .go ? .anthropicMessages : .chatCompletions
        }
        return .chatCompletions
    }

    private static func seededFormats(for tier: Tier) -> [String: OpenCodeZenAPIFormat] {
        switch tier {
        case .zen:
            return zenSeededFormats
        case .go:
            return goSeededFormats
        }
    }

    // https://opencode.ai/docs/zen/ endpoint table
    private static let zenSeededFormats: [String: OpenCodeZenAPIFormat] = [
        // Responses API
        "gpt-6-astra": .responses,
        "gpt-5.6-sol": .responses,
        "gpt-5.6-terra": .responses,
        "gpt-5.6-luna": .responses,
        "gpt-5.5": .responses,
        "gpt-5.5-pro": .responses,
        "gpt-5.4": .responses,
        "gpt-5.4-pro": .responses,
        "gpt-5.4-mini": .responses,
        "gpt-5.4-nano": .responses,
        "gpt-5.3-codex": .responses,
        "gpt-5.3-codex-spark": .responses,
        "gpt-5.2": .responses,
        "gpt-5.2-codex": .responses,
        "gpt-5.1": .responses,
        "gpt-5.1-codex": .responses,
        "gpt-5.1-codex-max": .responses,
        "gpt-5.1-codex-mini": .responses,
        "gpt-5": .responses,
        "gpt-5-codex": .responses,
        "gpt-5-nano": .responses,
        "grok-4.6": .responses,
        "grok-4.5": .responses,
        "grok-build-0.1": .responses,
        "muse-spark-1.3": .responses,
        "muse-spark-1.2": .responses,
        "muse-spark-1.3-contributor-free": .responses,
        "muse-spark-1.2-contributor-free": .responses,
        // Anthropic Messages API
        "claude-fable-5-1": .anthropicMessages,
        "claude-fable-5": .anthropicMessages,
        "claude-opus-5": .anthropicMessages,
        "claude-opus-4-8": .anthropicMessages,
        "claude-opus-4-7": .anthropicMessages,
        "claude-opus-4-6": .anthropicMessages,
        "claude-opus-4-5": .anthropicMessages,
        "claude-sonnet-5": .anthropicMessages,
        "claude-sonnet-4-6": .anthropicMessages,
        "claude-sonnet-4-5": .anthropicMessages,
        "claude-haiku-4-5": .anthropicMessages,
        "qwen3.7-max": .anthropicMessages,
        "qwen3.7-plus": .anthropicMessages,
        "qwen3.6-plus": .anthropicMessages,
        "qwen3.5-plus": .anthropicMessages,
        // Chat Completions API
        "deepseek-v4-pro": .chatCompletions,
        "deepseek-v4-flash": .chatCompletions,
        "deepseek-v4-flash-vision-exp": .chatCompletions,
        "minimax-m3": .chatCompletions,
        "minimax-m2.7": .chatCompletions,
        "minimax-m2.5": .chatCompletions,
        "glm-5.3-flash": .chatCompletions,
        "glm-5.3": .chatCompletions,
        "glm-5.2": .chatCompletions,
        "glm-5.1": .chatCompletions,
        "glm-5": .chatCompletions,
        "kimi-k2.5": .chatCompletions,
        "kimi-k2.6": .chatCompletions,
        "kimi-k2.7-code": .chatCompletions,
        "kimi-k3": .chatCompletions,
        "big-pickle": .chatCompletions,
        "mimo-v2.5-free": .chatCompletions,
        "ling-3.0-flash-fin-free": .chatCompletions,
        "nemotron-3-ultra-free": .chatCompletions,
        "nemotron-3.5-lightning-free": .chatCompletions,
    ]

    // https://opencode.ai/docs/go/ endpoint table
    private static let goSeededFormats: [String: OpenCodeZenAPIFormat] = [
        // Responses API
        "grok-4.6": .responses,
        "gpt-5.6-luna": .responses,
        "muse-spark-1.3-contributor": .responses,
        "muse-spark-1.2-contributor": .responses,
        // Anthropic Messages API
        "minimax-m3": .anthropicMessages,
        "minimax-m2.7": .anthropicMessages,
        "minimax-m2.5": .anthropicMessages,
        "qwen3.8-max": .anthropicMessages,
        "qwen3.8-flash": .anthropicMessages,
        "qwen3.7-max": .anthropicMessages,
        "qwen3.7-plus": .anthropicMessages,
        "qwen3.6-plus": .anthropicMessages,
        // Chat Completions API
        "glm-5.3-flash": .chatCompletions,
        "glm-5.3": .chatCompletions,
        "glm-5.2": .chatCompletions,
        "glm-5.1": .chatCompletions,
        "kimi-k3": .chatCompletions,
        "kimi-k2.7-code": .chatCompletions,
        "kimi-k2.6": .chatCompletions,
        "longcat-2.0": .chatCompletions,
        "deepseek-v4-pro": .chatCompletions,
        "deepseek-v4-flash": .chatCompletions,
        "deepseek-v4-flash-vision-exp": .chatCompletions,
        "mimo-v2.5": .chatCompletions,
        "mimo-v2.5-pro": .chatCompletions,
        "hy4-preview": .chatCompletions,
        "hy3": .chatCompletions,
        "omen-alpha": .chatCompletions,
    ]
}
