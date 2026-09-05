import Foundation
import Testing
@testable import Anvil

struct NativeCodingAgentAdapterTests {
    @Test
    func executableLookupSearchesPathAndCommonLocations() {
        let found = NativeCodingAgentAdapter.executableURL(
            for: .claudeCode,
            pathEnvironment: "/usr/bin:/custom/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { $0 == "/custom/bin/claude" }
        )
        #expect(found == URL(fileURLWithPath: "/custom/bin/claude"))

        let homebrew = NativeCodingAgentAdapter.executableURL(
            for: .openCode,
            pathEnvironment: "/usr/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { $0 == "/opt/homebrew/bin/opencode" }
        )
        #expect(homebrew == URL(fileURLWithPath: "/opt/homebrew/bin/opencode"))

        let missing = NativeCodingAgentAdapter.executableURL(
            for: .openCode,
            pathEnvironment: "/usr/bin",
            homeDirectory: URL(fileURLWithPath: "/home/test"),
            isExecutableFile: { _ in false }
        )
        #expect(missing == nil)
    }

    @Test
    func claudeLaunchSpecUsesStructuredArguments() {
        let agent = CustomCodingAgent(
            name: "Claude Code",
            command: "",
            promptDelivery: .standardInput,
            nativeAdapter: .claudeCode
        )
        let spec = NativeCodingAgentAdapter.launchSpec(
            for: agent,
            kind: .claudeCode,
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/claude"),
            prompt: "Build a timer"
        )
        #expect(spec.executableURL.path == "/opt/homebrew/bin/claude")
        #expect(spec.promptViaStandardInput)
        #expect(!spec.arguments.contains("Build a timer"))
        #expect(spec.arguments.contains("--output-format"))
        #expect(spec.arguments.contains("stream-json"))
        #expect(spec.arguments.contains("sonnet"))
        #expect(!spec.arguments.contains("--resume"))
    }

    @Test
    func claudeLaunchSpecResumesStoredSession() {
        let agent = CustomCodingAgent(
            name: "Claude Code",
            command: "",
            promptDelivery: .standardInput,
            nativeAdapter: .claudeCode,
            adapterModel: "opus",
            adapterMode: "plan"
        )
        let spec = NativeCodingAgentAdapter.launchSpec(
            for: agent,
            kind: .claudeCode,
            executableURL: URL(fileURLWithPath: "/usr/local/bin/claude"),
            prompt: "Change the color",
            resumeSessionID: "session-123"
        )
        #expect(spec.arguments.contains("--resume"))
        #expect(spec.arguments.contains("session-123"))
        #expect(spec.arguments.contains("opus"))
        #expect(spec.arguments.contains("plan"))
    }

    @Test
    func openCodeLaunchSpecPassesPromptAsArgument() {
        let agent = CustomCodingAgent(
            name: "OpenCode",
            command: "",
            promptDelivery: .placeholder,
            nativeAdapter: .openCode,
            adapterModel: "anthropic/claude-sonnet-4"
        )
        let spec = NativeCodingAgentAdapter.launchSpec(
            for: agent,
            kind: .openCode,
            executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/opencode"),
            prompt: "Build a timer"
        )
        #expect(!spec.promptViaStandardInput)
        #expect(spec.arguments.first == "run")
        #expect(spec.arguments.last == "Build a timer")
        #expect(spec.arguments.contains("-m"))
        #expect(spec.arguments.contains("anthropic/claude-sonnet-4"))
    }

    @Test
    func claudeSessionIDParsesStreamJSON() {
        let line = #"{"type":"system","subtype":"init","session_id":"abc-123"}"#
        #expect(NativeCodingAgentAdapter.claudeSessionID(fromStreamJSONLine: line) == "abc-123")
        #expect(NativeCodingAgentAdapter.claudeSessionID(fromStreamJSONLine: "not json") == nil)
        #expect(
            NativeCodingAgentAdapter.claudeSessionID(fromStreamJSONLine: #"{"type":"assistant"}"#)
                == nil
        )
    }

    @Test
    func agentSessionStoreRoundTrip() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-agent-session-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(AgentSessionStore.live.sessionID(root, "Claude Code") == nil)
        try AgentSessionStore.live.setSessionID(root, "Claude Code", "session-1")
        #expect(AgentSessionStore.live.sessionID(root, "Claude Code") == "session-1")
        try AgentSessionStore.live.setSessionID(root, "Claude Code", "session-2")
        #expect(AgentSessionStore.live.sessionID(root, "Claude Code") == "session-2")
    }

    @Test
    @MainActor
    func nativeAdapterSeedingIsIdempotent() {
        let store = CustomCodingAgentStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        #expect(store.agents.isEmpty)

        store.ensureNativeAdapterAgents(executableAvailable: { _ in true })
        #expect(store.agents.count == NativeCodingAgentKind.allCases.count)
        #expect(store.agents.allSatisfy { $0.nativeAdapter != nil })

        store.ensureNativeAdapterAgents(executableAvailable: { _ in true })
        #expect(store.agents.count == NativeCodingAgentKind.allCases.count)
    }

    @Test
    @MainActor
    func nativeAdapterSeedingSkipsMissingBinaries() {
        let store = CustomCodingAgentStore(userDefaults: UserDefaults(suiteName: UUID().uuidString)!)
        store.ensureNativeAdapterAgents(executableAvailable: { $0 == .claudeCode })
        #expect(store.agents.count == 1)
        #expect(store.agents.first?.nativeAdapter == .claudeCode)
    }
}
