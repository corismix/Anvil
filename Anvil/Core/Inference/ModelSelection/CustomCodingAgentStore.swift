import Foundation
import Observation

nonisolated struct CustomCodingAgent: Codable, Equatable, Identifiable, Sendable {
    enum PromptDelivery: String, Codable, CaseIterable, Sendable {
        case placeholder
        case standardInput = "standard_input"
    }

    let id: UUID
    var name: String
    var command: String
    var promptDelivery: PromptDelivery
    /// Set when this entry is backed by a native adapter (OpenCode,
    /// Claude Code): the CLI is launched directly with structured
    /// arguments and `command` is unused.
    var nativeAdapter: NativeCodingAgentKind?
    /// Adapter-specific model override (nil uses the adapter default).
    var adapterModel: String?
    /// Adapter-specific mode (OpenCode agent mode, Claude Code permission
    /// mode; nil uses the adapter default).
    var adapterMode: String?

    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        promptDelivery: PromptDelivery = .placeholder,
        nativeAdapter: NativeCodingAgentKind? = nil,
        adapterModel: String? = nil,
        adapterMode: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.promptDelivery = promptDelivery
        self.nativeAdapter = nativeAdapter
        self.adapterModel = adapterModel
        self.adapterMode = adapterMode
    }
}

nonisolated enum CustomCodingAgentPreset: String, CaseIterable, Identifiable, Sendable {
    case claudeCode = "claude_code"
    case openCode = "open_code"
    case custom

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .claudeCode: "Claude Code"
        case .openCode: "OpenCode"
        case .custom: "Custom"
        }
    }

    var agent: CustomCodingAgent {
        switch self {
        case .claudeCode:
            CustomCodingAgent(
                name: displayName,
                command: "claude -p --permission-mode auto --output-format stream-json --verbose --model sonnet",
                promptDelivery: .standardInput
            )
        case .openCode:
            CustomCodingAgent(
                name: displayName,
                command: "opencode run {{prompt}}"
            )
        case .custom:
            CustomCodingAgent(name: "", command: "")
        }
    }
}

enum CustomCodingAgentValidationError: LocalizedError, Equatable {
    case missingName
    case duplicateName
    case missingCommand
    case invalidPlaceholderCount
    case placeholderNotAllowedWithStandardInput

    var errorDescription: String? {
        switch self {
        case .missingName:
            "Enter a name for this coding agent."
        case .duplicateName:
            "Another coding agent already uses this name."
        case .missingCommand:
            "Enter the command Anvil should run."
        case .invalidPlaceholderCount:
            "The command must contain {{prompt}} exactly once."
        case .placeholderNotAllowedWithStandardInput:
            "Remove {{prompt}} when sending the prompt through standard input."
        }
    }
}

@MainActor
@Observable
final class CustomCodingAgentStore {
    private enum Key {
        static let agents = "generation.customCodingAgents"
        static let selectedAgentID = "generation.selectedCustomCodingAgentID"
    }

    private(set) var agents: [CustomCodingAgent]
    var selectedAgentID: UUID? {
        didSet {
            if let selectedAgentID {
                userDefaults.set(selectedAgentID.uuidString, forKey: Key.selectedAgentID)
            } else {
                userDefaults.removeObject(forKey: Key.selectedAgentID)
            }
        }
    }

    @ObservationIgnored private let userDefaults: UserDefaults

    init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
        if let data = userDefaults.data(forKey: Key.agents),
           let decoded = try? JSONDecoder().decode([CustomCodingAgent].self, from: data)
        {
            agents = decoded
        } else {
            agents = []
        }
        selectedAgentID = userDefaults.string(forKey: Key.selectedAgentID).flatMap {
            UUID(uuidString: $0)
        }
        if selectedAgentID.map({ id in !agents.contains(where: { $0.id == id }) }) == true {
            selectedAgentID = nil
        }
    }

    var selectedAgent: CustomCodingAgent? {
        guard let selectedAgentID else { return nil }
        return agents.first { $0.id == selectedAgentID }
    }

    func validate(_ agent: CustomCodingAgent) throws -> CustomCodingAgent {
        var validated = agent
        validated.name = agent.name.trimmingCharacters(in: .whitespacesAndNewlines)
        validated.command = agent.command.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !validated.name.isEmpty else {
            throw CustomCodingAgentValidationError.missingName
        }
        guard !agents.contains(where: {
            $0.id != validated.id
                && $0.name.compare(validated.name, options: [.caseInsensitive, .diacriticInsensitive])
                    == .orderedSame
        }) else {
            throw CustomCodingAgentValidationError.duplicateName
        }
        if validated.nativeAdapter == nil {
            guard !validated.command.isEmpty else {
                throw CustomCodingAgentValidationError.missingCommand
            }

            let placeholderCount = validated.command.components(separatedBy: "{{prompt}}").count - 1
            switch validated.promptDelivery {
            case .placeholder:
                guard placeholderCount == 1 else {
                    throw CustomCodingAgentValidationError.invalidPlaceholderCount
                }
            case .standardInput:
                guard placeholderCount == 0 else {
                    throw CustomCodingAgentValidationError.placeholderNotAllowedWithStandardInput
                }
            }
        }
        return validated
    }

    /// Inserts native adapter entries (OpenCode, Claude Code) for CLIs
    /// found on this machine. Idempotent per adapter kind.
    func ensureNativeAdapterAgents(
        executableAvailable: (NativeCodingAgentKind) -> Bool = {
            NativeCodingAgentAdapter.executableURL(for: $0) != nil
        }
    ) {
        var changed = false
        for kind in NativeCodingAgentKind.allCases {
            guard !agents.contains(where: { $0.nativeAdapter == kind }),
                  executableAvailable(kind)
            else { continue }
            agents.append(
                CustomCodingAgent(
                    name: kind.displayName,
                    command: "",
                    promptDelivery: .standardInput,
                    nativeAdapter: kind
                )
            )
            changed = true
        }
        if changed {
            persistAgents()
        }
    }

    @discardableResult
    func save(_ agent: CustomCodingAgent) throws -> CustomCodingAgent {
        let validated = try validate(agent)
        if let index = agents.firstIndex(where: { $0.id == validated.id }) {
            agents[index] = validated
        } else {
            agents.append(validated)
        }
        persistAgents()
        return validated
    }

    func delete(id: UUID) {
        agents.removeAll { $0.id == id }
        if selectedAgentID == id {
            selectedAgentID = nil
        }
        persistAgents()
    }

    private func persistAgents() {
        guard let data = try? JSONEncoder().encode(agents) else { return }
        userDefaults.set(data, forKey: Key.agents)
    }
}
