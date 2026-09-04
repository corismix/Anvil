import Foundation
import Testing
@testable import Anvil

struct ToolGitClientTests {
    @Test
    func ensureRepositoryCreatesRepoAndGitignoreIdempotently() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        #expect(try client.ensureRepository(root))
        #expect(FileManager.default.fileExists(
            atPath: root.appendingPathComponent(".git", isDirectory: true).path
        ))
        let gitignore = try String(
            contentsOf: root.appendingPathComponent(".gitignore"),
            encoding: .utf8
        )
        #expect(gitignore.contains(".build/"))
        #expect(gitignore.contains(".anvil/versions/"))

        // Second call is a no-op.
        #expect(try !client.ensureRepository(root))
    }

    @Test
    func recordVersionCommitsAndSkipsCleanTree() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        try Self.write("one", to: root, name: "ContentView.swift")

        #expect(try client.recordVersion(root, "Initial version"))
        #expect(try client.commitCount(root) == 1)

        // No changes -> no commit.
        #expect(try !client.recordVersion(root, "Nothing changed"))
        #expect(try client.commitCount(root) == 1)

        try Self.write("two", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Edit: change things"))
        #expect(try client.commitCount(root) == 2)
    }

    @Test
    func historyReturnsNewestFirstWithSubjects() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        try Self.write("one", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Initial version"))
        try Self.write("two", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Edit: second pass"))

        let history = try client.history(root, 10)
        #expect(history.count == 2)
        #expect(history[0].subject == "Edit: second pass")
        #expect(history[1].subject == "Initial version")
        #expect(history[0].sha != history[1].sha)
        #expect(history[0].date != .distantPast)
    }

    @Test
    func historyAndCommitCountAreEmptyWithoutRepo() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        #expect(try client.history(root, 10).isEmpty)
        #expect(try client.commitCount(root) == 0)
    }

    @Test
    func restoreVersionChecksOutTrackedFiles() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        try Self.write("original", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Initial version"))
        let history = try client.history(root, 10)
        let originalSHA = try #require(history.first?.sha)

        try Self.write("edited", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Edit: change"))

        try client.restoreVersion(root, originalSHA)
        let restored = try String(
            contentsOf: root.appendingPathComponent("ContentView.swift"),
            encoding: .utf8
        )
        #expect(restored == "original")

        // The restore is staged; committing it keeps history linear.
        #expect(try client.recordVersion(root, "Restore to \(originalSHA.prefix(7))"))
        #expect(try client.commitCount(root) == 3)
    }

    @Test
    func diffFromShowsWorkingTreeChanges() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        try Self.write("before", to: root, name: "ContentView.swift")
        #expect(try client.recordVersion(root, "Initial version"))
        let sha = try #require(try client.history(root, 1).first?.sha)

        try Self.write("after", to: root, name: "ContentView.swift")
        let diff = try client.diffFrom(root, sha)
        #expect(diff.contains("-before"))
        #expect(diff.contains("+after"))
    }

    @Test
    func gitignoredArtifactsAreNotCommitted() throws {
        let root = try Self.makeTemporaryPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        let client = ToolGitClient.system
        try Self.write("source", to: root, name: "ContentView.swift")
        let buildDir = root.appendingPathComponent(".build", isDirectory: true)
        try FileManager.default.createDirectory(at: buildDir, withIntermediateDirectories: true)
        try Self.write("artifact", to: buildDir, name: "binary.o")
        let versionsDir = root
            .appendingPathComponent(".anvil/versions", isDirectory: true)
        try FileManager.default.createDirectory(
            at: versionsDir,
            withIntermediateDirectories: true
        )
        try Self.write("staged", to: versionsDir, name: "pending-ContentView.swift")

        #expect(try client.recordVersion(root, "Initial version"))
        // Only ContentView.swift and .gitignore are tracked.
        #expect(try !client.recordVersion(root, "should be clean"))
        let diff = try client.diffFrom(root, "HEAD")
        #expect(diff.isEmpty)
    }

    private static func makeTemporaryPackageRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-git-tests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private static func write(_ contents: String, to directory: URL, name: String) throws {
        try contents.write(
            to: directory.appendingPathComponent(name),
            atomically: true,
            encoding: .utf8
        )
    }
}
