import Foundation

/// An agent CLI Anvil knows natively and launches directly (executable +
/// argument array), never through a shell command string.
enum NativeCodingAgentKind: String, Codable, CaseIterable, Sendable {
    case openCode = "open_code_native"
    case claudeCode = "claude_code_native"

    var displayName: String {
        switch self {
        case .openCode: "OpenCode"
        case .claudeCode: "Claude Code"
        }
    }

    var executableName: String {
        switch self {
        case .openCode: "opencode"
        case .claudeCode: "claude"
        }
    }

    var defaultModel: String {
        switch self {
        case .openCode: ""
        case .claudeCode: "sonnet"
        }
    }

    /// Whether the adapter can resume a prior session for follow-up edits.
    var supportsSessionResume: Bool {
        switch self {
        case .openCode: false
        case .claudeCode: true
        }
    }
}

/// How a native adapter process is launched: a resolved executable and its
/// arguments, with no shell involved.
nonisolated struct NativeCodingAgentLaunchSpec: Equatable, Sendable {
    var executableURL: URL
    var arguments: [String]
    var promptViaStandardInput: Bool
}

nonisolated enum NativeCodingAgentAdapter {
    /// Resolves the adapter's executable: every PATH entry, then common
    /// install locations. Returns nil when the CLI is not installed.
    static func executableURL(
        for kind: NativeCodingAgentKind,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutableFile: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        var directories = pathEnvironment.split(separator: ":").map(String.init)
        directories.append(homeDirectory.appendingPathComponent(".local/bin").path)
        directories.append("/opt/homebrew/bin")
        directories.append("/usr/local/bin")
        for directory in directories where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(kind.executableName).path
            if isExecutableFile(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    /// Builds the structured launch for a native adapter agent.
    static func launchSpec(
        for agent: CustomCodingAgent,
        kind: NativeCodingAgentKind,
        executableURL: URL,
        prompt: String,
        resumeSessionID: String? = nil
    ) -> NativeCodingAgentLaunchSpec {
        switch kind {
        case .claudeCode:
            var arguments = [
                "-p",
                "--permission-mode", agent.adapterMode ?? "auto",
                "--output-format", "stream-json",
                "--verbose",
                "--model", agent.adapterModel ?? kind.defaultModel,
            ]
            if let resumeSessionID, !resumeSessionID.isEmpty {
                arguments.append(contentsOf: ["--resume", resumeSessionID])
            }
            return NativeCodingAgentLaunchSpec(
                executableURL: executableURL,
                arguments: arguments,
                promptViaStandardInput: true
            )
        case .openCode:
            // Non-interactive runs auto-reject every permission prompt unless
            // --auto is passed, which would leave the agent unable to edit
            // files or run builds. Anvil's workspace is the guardrail instead
            // (protected files, dependency approval), same as Claude Code's
            // --permission-mode auto.
            var arguments = ["run", "--auto"]
            if let model = agent.adapterModel, !model.isEmpty {
                arguments.append(contentsOf: ["-m", model])
            }
            if let mode = agent.adapterMode, !mode.isEmpty {
                arguments.append(contentsOf: ["--agent", mode])
            }
            arguments.append(prompt)
            return NativeCodingAgentLaunchSpec(
                executableURL: executableURL,
                arguments: arguments,
                promptViaStandardInput: false
            )
        }
    }

    /// Extracts the session id from a Claude Code stream-json stdout line,
    /// for later `--resume`.
    static func claudeSessionID(fromStreamJSONLine line: String) -> String? {
        guard let data = line.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let sessionID = object["session_id"] as? String,
              !sessionID.isEmpty
        else { return nil }
        return sessionID
    }
}

/// Per-app record of the latest agent session id, kept in the committed
/// `.anvil/` metadata so follow-up edits can resume the prior session.
nonisolated struct AgentSessionStore: Sendable {
    var sessionID: @Sendable (_ packageRootURL: URL, _ agentName: String) -> String?
    var setSessionID: @Sendable (_ packageRootURL: URL, _ agentName: String, _ sessionID: String) throws -> Void

    static let live = AgentSessionStore(
        sessionID: { packageRootURL, agentName in
            let url = fileURL(for: packageRootURL)
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data)
            else { return nil }
            return payload.sessions[agentName]
        },
        setSessionID: { packageRootURL, agentName, sessionID in
            let url = fileURL(for: packageRootURL)
            var payload = (try? Data(contentsOf: url))
                .flatMap { try? JSONDecoder().decode(Payload.self, from: $0) }
                ?? Payload(sessions: [:])
            payload.sessions[agentName] = sessionID
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(payload).write(to: url, options: .atomic)
        }
    )

    private static func fileURL(for packageRootURL: URL) -> URL {
        ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
            .appendingPathComponent("agent-session.json")
    }

    private struct Payload: Codable {
        var sessions: [String: String]
    }
}
