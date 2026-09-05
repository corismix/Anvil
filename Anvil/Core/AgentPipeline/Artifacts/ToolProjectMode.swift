import Foundation

/// Size mode of a generated app: today's single-file loop, or a multi-file
/// project. Persisted as a sidecar in the package metadata directory so it
/// travels with the package (and its git history) instead of the SwiftData
/// schema.
enum ToolProjectMode: String, Codable, Equatable, Sendable {
    case tiny
    case project
}

nonisolated struct ToolProjectModeStore: Sendable {
    var mode: @Sendable (_ packageRootURL: URL) -> ToolProjectMode
    var setMode: @Sendable (_ packageRootURL: URL, _ mode: ToolProjectMode) throws -> Void

    static let live = ToolProjectModeStore(
        mode: { packageRootURL in
            let url = fileURL(for: packageRootURL)
            guard let data = try? Data(contentsOf: url),
                  let payload = try? JSONDecoder().decode(Payload.self, from: data),
                  let mode = ToolProjectMode(rawValue: payload.mode)
            else { return .tiny }
            return mode
        },
        setMode: { packageRootURL, mode in
            let url = fileURL(for: packageRootURL)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(Payload(mode: mode.rawValue))
                .write(to: url, options: .atomic)
        }
    )

    private static func fileURL(for packageRootURL: URL) -> URL {
        ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
            .appendingPathComponent("project-mode.json")
    }

    private struct Payload: Codable {
        var mode: String
    }
}

/// A third-party Swift package dependency the agent requested for an app.
/// Requests are never applied directly: the user allows or rejects each
/// one, and the decision is remembered per app in the package metadata.
struct ToolPackageDependencyRequest: Codable, Hashable, Sendable {
    var package: String
    var from: String
    var product: String
}

nonisolated struct ToolPackageDependencyStore: Sendable {
    var pendingRequest: @Sendable (_ packageRootURL: URL) -> [ToolPackageDependencyRequest]
    var clearPendingRequest: @Sendable (_ packageRootURL: URL) throws -> Void
    var allowed: @Sendable (_ packageRootURL: URL) -> [ToolPackageDependencyRequest]
    var setAllowed: @Sendable (_ packageRootURL: URL, _ dependencies: [ToolPackageDependencyRequest]) throws -> Void
    var rejected: @Sendable (_ packageRootURL: URL) -> [ToolPackageDependencyRequest]
    var setRejected: @Sendable (_ packageRootURL: URL, _ dependencies: [ToolPackageDependencyRequest]) throws -> Void

    static let live = ToolPackageDependencyStore(
        pendingRequest: { packageRootURL in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("package-request.json")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([ToolPackageDependencyRequest].self, from: data)) ?? []
        },
        clearPendingRequest: { packageRootURL in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("package-request.json")
            try? FileManager.default.removeItem(at: url)
        },
        allowed: { packageRootURL in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("allowed-dependencies.json")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([ToolPackageDependencyRequest].self, from: data)) ?? []
        },
        setAllowed: { packageRootURL, dependencies in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("allowed-dependencies.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(dependencies).write(to: url, options: .atomic)
        },
        rejected: { packageRootURL in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("rejected-dependencies.json")
            guard let data = try? Data(contentsOf: url) else { return [] }
            return (try? JSONDecoder().decode([ToolPackageDependencyRequest].self, from: data)) ?? []
        },
        setRejected: { packageRootURL, dependencies in
            let url = ToolPackageLayout.packageMetadataDirectoryURL(for: packageRootURL)
                .appendingPathComponent("rejected-dependencies.json")
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try JSONEncoder().encode(dependencies).write(to: url, options: .atomic)
        }
    )
}
