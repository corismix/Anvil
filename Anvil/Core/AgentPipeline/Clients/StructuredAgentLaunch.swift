import Foundation

/// A custom coding agent launch defined as executable + argument template
/// + environment, run directly with no shell involved.
nonisolated struct StructuredAgentLaunch: Codable, Equatable, Sendable {
    /// Absolute path, or a bare name resolved against PATH and the common
    /// install directories.
    var executable: String = ""
    /// Ordered argument template. `{{prompt}}` inside any argument is
    /// replaced by the prompt text as part of that single argv element;
    /// with no token anywhere, the prompt goes to stdin.
    var arguments: [String] = []
    /// Extra environment entries merged over a minimal inherited base.
    var environment: [String: String] = [:]
    /// 0 means no timeout; otherwise the process group is killed after
    /// this many seconds.
    var timeoutSeconds: Int = 0
}

nonisolated enum StructuredAgentLaunchError: LocalizedError, Equatable {
    case missingExecutable
    case executableNotFound(String)
    case invalidEnvironmentKey(String)

    var errorDescription: String? {
        switch self {
        case .missingExecutable:
            "Enter the executable Anvil should run."
        case .executableNotFound(let executable):
            "\(executable) was not found. Use an absolute path or a command on PATH."
        case .invalidEnvironmentKey(let key):
            "Invalid environment variable name: \(key)"
        }
    }
}

nonisolated enum StructuredAgentLaunchResolver {
    static let promptToken = "{{prompt}}"

    /// Environment keys inherited from the Anvil process for structured
    /// launches; everything else must be declared on the agent.
    static let inheritedEnvironmentKeys = ["PATH", "HOME", "LANG", "USER", "TMPDIR"]

    static func resolveExecutable(
        _ executable: String,
        pathEnvironment: String = ProcessInfo.processInfo.environment["PATH"] ?? "",
        homeDirectory: URL = FileManager.default.homeDirectoryForCurrentUser,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) -> URL? {
        let executable = executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else { return nil }
        if executable.contains("/") {
            return isExecutableFile(executable) ? URL(fileURLWithPath: executable) : nil
        }
        var directories = pathEnvironment.split(separator: ":").map(String.init)
        directories.append(homeDirectory.appendingPathComponent(".local/bin").path)
        directories.append("/opt/homebrew/bin")
        directories.append("/usr/local/bin")
        for directory in directories where !directory.isEmpty {
            let candidate = URL(fileURLWithPath: directory)
                .appendingPathComponent(executable).path
            if isExecutableFile(candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }
        return nil
    }

    static func validate(
        _ launch: StructuredAgentLaunch,
        isExecutableFile: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }
    ) throws {
        let executable = launch.executable.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !executable.isEmpty else {
            throw StructuredAgentLaunchError.missingExecutable
        }
        guard resolveExecutable(launch.executable, isExecutableFile: isExecutableFile) != nil
        else {
            throw StructuredAgentLaunchError.executableNotFound(executable)
        }
        for key in launch.environment.keys {
            guard !key.isEmpty,
                  key.allSatisfy({ $0.isLetter || $0.isNumber || $0 == "_" }),
                  key.first?.isNumber == false
            else {
                throw StructuredAgentLaunchError.invalidEnvironmentKey(key)
            }
        }
    }

    /// Applies the prompt to the argument template. Returns the final
    /// argv and whether the prompt should instead be written to stdin.
    static func resolvedArguments(
        _ launch: StructuredAgentLaunch,
        prompt: String
    ) -> (arguments: [String], promptViaStandardInput: Bool) {
        var sawPromptToken = false
        let arguments = launch.arguments.map { argument -> String in
            guard argument.contains(promptToken) else { return argument }
            sawPromptToken = true
            return argument.replacingOccurrences(of: promptToken, with: prompt)
        }
        return (arguments, !sawPromptToken)
    }

    static func mergedEnvironment(
        _ launch: StructuredAgentLaunch,
        base: [String: String] = ProcessInfo.processInfo.environment
    ) -> [String: String] {
        var environment = base.filter { inheritedEnvironmentKeys.contains($0.key) }
        for (key, value) in launch.environment {
            environment[key] = value
        }
        return environment
    }

    /// Conservative conversion of a legacy shell command string into a
    /// structured launch. Returns nil for anything that uses shell
    /// features (pipes, redirects, expansion, subshells, globs): those
    /// stay legacy.
    static func parseLegacyCommand(_ command: String) -> StructuredAgentLaunch? {
        let shellMetacharacters: Set<Character> = ["|", ";", "&", ">", "<", "$", "`", "*", "?", "(", ")", "{", "}", "[", "]", "~", "#", "\\", "\n", "\r"]
        // {{prompt}} is checked before metacharacter rejection, so allow its braces.
        let scrubbed = command.replacingOccurrences(of: promptToken, with: "PROMPT_TOKEN")
        guard !scrubbed.contains(where: { shellMetacharacters.contains($0) }) else {
            return nil
        }
        guard let tokens = tokenize(command), let executable = tokens.first, !executable.isEmpty
        else { return nil }
        return StructuredAgentLaunch(
            executable: executable,
            arguments: Array(tokens.dropFirst()),
            environment: [:],
            timeoutSeconds: 0
        )
    }

    /// Whitespace tokenizer honoring single and double quotes.
    private static func tokenize(_ command: String) -> [String]? {
        var tokens: [String] = []
        var current = ""
        var quote: Character?
        var hasContent = false
        for character in command {
            if let activeQuote = quote {
                if character == activeQuote {
                    quote = nil
                } else {
                    current.append(character)
                }
                continue
            }
            switch character {
            case "'", "\"":
                quote = character
                hasContent = true
            case " ", "\t":
                if hasContent || !current.isEmpty {
                    tokens.append(current)
                    current = ""
                    hasContent = false
                }
            default:
                current.append(character)
                hasContent = true
            }
        }
        guard quote == nil else { return nil }
        if hasContent || !current.isEmpty {
            tokens.append(current)
        }
        return tokens.isEmpty ? nil : tokens
    }
}
