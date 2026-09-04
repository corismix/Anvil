import Foundation

struct ToolGitCommit: Equatable, Sendable {
    let sha: String
    let subject: String
    let date: Date
}

/// Git-backed per-tool version history. Each generated app package is its
/// own git repo; commits happen at accepted-result boundaries (create,
/// edit, icon change, restore). Git is auxiliary: call sites treat failures
/// as non-fatal so generation never breaks because git did.
struct ToolGitClient: Sendable {
    /// Creates the repo (and `.gitignore`) when missing. Returns true when
    /// the repo was created by this call.
    var ensureRepository: @Sendable (_ packageRootURL: URL) throws -> Bool
    /// `git add -A` + commit with the Anvil identity. Returns false when the
    /// tree was clean (nothing to commit).
    var recordVersion: @Sendable (_ packageRootURL: URL, _ message: String) throws -> Bool
    /// Newest-first commit list.
    var history: @Sendable (_ packageRootURL: URL, _ limit: Int) throws -> [ToolGitCommit]
    /// Unified diff between a commit and the current working tree.
    var diffFrom: @Sendable (_ packageRootURL: URL, _ sha: String) throws -> String
    /// Checks out all tracked files from `sha` into the working tree.
    /// Caller follows with `recordVersion` to keep history linear.
    var restoreVersion: @Sendable (_ packageRootURL: URL, _ sha: String) throws -> Void
    var commitCount: @Sendable (_ packageRootURL: URL) throws -> Int

    /// Inert variant: reports no history and records nothing. Used under
    /// `swift test` (ANVIL_RUNNING_TESTS=1) so unit tests never shell out
    /// to git; ToolGitClientTests exercises `system` directly.
    nonisolated static let disabled = ToolGitClient(
        ensureRepository: { _ in false },
        recordVersion: { _, _ in false },
        history: { _, _ in [] },
        diffFrom: { _, _ in "" },
        restoreVersion: { _, _ in
            throw ToolGitError.commandFailed(command: "git checkout", stderr: "git is disabled")
        },
        commitCount: { _ in 0 }
    )

    /// The live client used by the app: real git, except under the test
    /// runner where it stays inert to keep unit tests fast and isolated.
    nonisolated static var live: ToolGitClient {
        if ProcessInfo.processInfo.environment["ANVIL_RUNNING_TESTS"] == "1" {
            return .disabled
        }
        return .system
    }

    /// Real git implementation.
    nonisolated static let system = ToolGitClient(
        ensureRepository: { packageRootURL in
            let gitDirectory = packageRootURL.appendingPathComponent(".git", isDirectory: true)
            guard !FileManager.default.fileExists(atPath: gitDirectory.path) else {
                return false
            }
            try FileManager.default.createDirectory(
                at: packageRootURL,
                withIntermediateDirectories: true
            )
            let gitignoreURL = packageRootURL.appendingPathComponent(".gitignore")
            if !FileManager.default.fileExists(atPath: gitignoreURL.path) {
                try Self.gitignoreContents.write(
                    to: gitignoreURL,
                    atomically: true,
                    encoding: .utf8
                )
            }
            try Self.runGit(packageRootURL, ["init", "--quiet"])
            return true
        },
        recordVersion: { packageRootURL, message in
            _ = try Self.ensureRepositoryIfNeeded(packageRootURL)
            try Self.runGit(packageRootURL, ["add", "-A"])
            let status = try Self.runGit(packageRootURL, ["status", "--porcelain"])
            guard !status.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                return false
            }
            try Self.runGit(
                packageRootURL,
                [
                    "-c", "user.name=Anvil",
                    "-c", "user.email=anvil@localhost",
                    "commit", "--quiet", "-m", message
                ]
            )
            return true
        },
        history: { packageRootURL, limit in
            guard try Self.hasCommits(packageRootURL) else { return [] }
            let output = try Self.runGit(
                packageRootURL,
                [
                    "log",
                    "--max-count=\(max(1, limit))",
                    "--format=%H%x1f%aI%x1f%s"
                ]
            )
            let iso = ISO8601DateFormatter()
            return output
                .split(whereSeparator: \.isNewline)
                .compactMap { line -> ToolGitCommit? in
                    let fields = line.split(separator: "\u{1f}", maxSplits: 2)
                    guard fields.count == 3 else { return nil }
                    return ToolGitCommit(
                        sha: String(fields[0]),
                        subject: String(fields[2]),
                        date: iso.date(from: String(fields[1])) ?? .distantPast
                    )
                }
        },
        diffFrom: { packageRootURL, sha in
            try Self.runGit(packageRootURL, ["diff", sha, "--", "."])
        },
        restoreVersion: { packageRootURL, sha in
            try Self.runGit(packageRootURL, ["checkout", sha, "--", "."])
        },
        commitCount: { packageRootURL in
            guard try Self.hasCommits(packageRootURL) else { return 0 }
            let output = try Self.runGit(packageRootURL, ["rev-list", "--count", "HEAD"])
            return Int(output.trimmingCharacters(in: .whitespacesAndNewlines)) ?? 0
        }
    )

    nonisolated static let gitignoreContents = """
        .build/
        .codex/
        *.app
        .anvil/versions/
        .anvil/pending-*
        .anvil/attachments/current-run/
        .anvil/custom-agent-transcripts/
        .ironsmith/versions/
        .ironsmith/pending-*
        .ironsmith/attachments/current-run/
        .ironsmith/custom-agent-transcripts/

        """

    nonisolated private static func ensureRepositoryIfNeeded(
        _ packageRootURL: URL
    ) throws -> Bool {
        try system.ensureRepository(packageRootURL)
    }

    nonisolated private static func hasCommits(_ packageRootURL: URL) throws -> Bool {
        let gitDirectory = packageRootURL.appendingPathComponent(".git", isDirectory: true)
        guard FileManager.default.fileExists(atPath: gitDirectory.path) else {
            return false
        }
        let result = try runGitResult(packageRootURL, ["rev-parse", "--verify", "HEAD"])
        return result.terminationStatus == 0
    }

    @discardableResult
    nonisolated private static func runGit(
        _ packageRootURL: URL,
        _ arguments: [String]
    ) throws -> String {
        let result = try runGitResult(packageRootURL, arguments)
        guard result.terminationStatus == 0 else {
            throw ToolGitError.commandFailed(
                command: "git \(arguments.joined(separator: " "))",
                stderr: result.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
        return result.stdout
    }

    nonisolated private static func runGitResult(
        _ packageRootURL: URL,
        _ arguments: [String]
    ) throws -> (terminationStatus: Int32, stdout: String, stderr: String) {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = ["-C", packageRootURL.path] + arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        try process.run()

        // Read both pipes on background queues before waiting so a large
        // diff cannot fill a pipe buffer and deadlock the process.
        let group = DispatchGroup()
        var outputData = Data()
        var errorData = Data()
        group.enter()
        DispatchQueue.global().async {
            outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        group.enter()
        DispatchQueue.global().async {
            errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
            group.leave()
        }
        process.waitUntilExit()
        group.wait()
        return (
            process.terminationStatus,
            String(data: outputData, encoding: .utf8) ?? "",
            String(data: errorData, encoding: .utf8) ?? ""
        )
    }
}

enum ToolGitError: LocalizedError, Equatable {
    case commandFailed(command: String, stderr: String)

    var errorDescription: String? {
        switch self {
        case let .commandFailed(command, stderr):
            return "Version history command failed (\(command)): \(stderr)"
        }
    }
}
