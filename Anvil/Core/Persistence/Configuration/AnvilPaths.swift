import Foundation

nonisolated enum AnvilPaths {
    static let databaseFileName = "anvil.sqlite"
    /// Pre-rebrand installs stored data in ~/.ironsmith with ironsmith.sqlite.
    static let legacyDatabaseFileName = "ironsmith.sqlite"

    static var rootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".anvil", isDirectory: true)
    }

    static var legacyRootDirectory: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".ironsmith", isDirectory: true)
    }

    /// Moves pre-rebrand data (~/.ironsmith -> ~/.anvil, ironsmith.sqlite ->
    /// anvil.sqlite) before SwiftData opens the store. Runs once at startup;
    /// a no-op for fresh installs and after migration.
    static func migrateLegacyDataIfNeeded(
        fileManager: FileManager = .default,
        legacyRoot: URL? = nil,
        currentRoot: URL? = nil
    ) throws {
        let legacyRoot = legacyRoot ?? legacyRootDirectory
        let currentRoot = currentRoot ?? rootDirectory

        if !fileManager.fileExists(atPath: currentRoot.path),
           fileManager.fileExists(atPath: legacyRoot.path) {
            try fileManager.moveItem(at: legacyRoot, to: currentRoot)
        }

        let databaseDirectory = currentRoot
            .appendingPathComponent("db", isDirectory: true)
        let legacyDatabaseURL = databaseDirectory
            .appendingPathComponent(legacyDatabaseFileName)
        let currentDatabaseURL = databaseDirectory
            .appendingPathComponent(databaseFileName)
        guard fileManager.fileExists(atPath: legacyDatabaseURL.path),
              !fileManager.fileExists(atPath: currentDatabaseURL.path)
        else {
            return
        }
        for suffix in ["", "-wal", "-shm", "-journal"] {
            let source = databaseDirectory
                .appendingPathComponent(legacyDatabaseFileName + suffix)
            let destination = databaseDirectory
                .appendingPathComponent(databaseFileName + suffix)
            if fileManager.fileExists(atPath: source.path) {
                try fileManager.moveItem(at: source, to: destination)
            }
        }
    }

    static var databaseDirectory: URL {
        rootDirectory.appendingPathComponent("db", isDirectory: true)
    }

    static var databaseURL: URL {
        databaseDirectory.appendingPathComponent(databaseFileName)
    }

    static var databaseBackupsDirectory: URL {
        databaseDirectory.appendingPathComponent("backups", isDirectory: true)
    }

    static var modelsDirectory: URL {
        rootDirectory.appendingPathComponent("models", isDirectory: true)
    }

    static var toolsDirectory: URL {
        rootDirectory.appendingPathComponent("tools", isDirectory: true)
    }

    static var codexHomeDirectory: URL {
        rootDirectory.appendingPathComponent(".codex", isDirectory: true)
    }

    static var codexAuthFileURL: URL {
        codexHomeDirectory.appendingPathComponent("auth.json")
    }

    static var agentDiagnosticsLogURL: URL {
        rootDirectory.appendingPathComponent("agent-diagnostics.log")
    }

    static func ensureDirectoriesExist() throws {
        for directory in [
            databaseDirectory,
            databaseBackupsDirectory,
            modelsDirectory,
            toolsDirectory,
            codexHomeDirectory,
        ] {
            try FileManager.default.createDirectory(
                at: directory,
                withIntermediateDirectories: true
            )
        }
    }
}
