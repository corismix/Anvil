import Foundation
import Testing
@testable import Anvil

struct AgentPipelineProjectModeTests {
    private func makeTempPackageRoot() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("anvil-project-mode-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test
    func projectModeDefaultsToTinyAndPersists() throws {
        let root = try makeTempPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }

        #expect(ToolProjectModeStore.live.mode(root) == .tiny)
        try ToolProjectModeStore.live.setMode(root, .project)
        #expect(ToolProjectModeStore.live.mode(root) == .project)
        try ToolProjectModeStore.live.setMode(root, .tiny)
        #expect(ToolProjectModeStore.live.mode(root) == .tiny)
    }

    @Test
    func dependencyStoreRoundTrip() throws {
        let root = try makeTempPackageRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = ToolPackageDependencyStore.live
        let request = ToolPackageDependencyRequest(
            package: "https://github.com/apple/swift-algorithms.git",
            from: "1.2.0",
            product: "Algorithms"
        )

        #expect(store.pendingRequest(root).isEmpty)
        #expect(store.allowed(root).isEmpty)
        #expect(store.rejected(root).isEmpty)

        try store.setAllowed(root, [request])
        try store.setRejected(root, [request])
        #expect(store.allowed(root) == [request])
        #expect(store.rejected(root) == [request])
    }

    @Test
    func packageManifestIncludesDependencies() throws {
        let layout = ToolPackageLayout(
            packageRootURL: URL(fileURLWithPath: "/tmp/sample"),
            executableName: "SampleApp"
        )
        let plain = layout.packageManifestContent()
        #expect(!plain.contains("dependencies: ["))

        let withDependencies = layout.packageManifestContent(
            dependencies: [
                ToolPackageDependencyRequest(
                    package: "https://github.com/apple/swift-algorithms.git",
                    from: "1.2.0",
                    product: "Algorithms"
                )
            ]
        )
        #expect(
            withDependencies.contains(
                ".package(url: \"https://github.com/apple/swift-algorithms.git\", from: \"1.2.0\")"
            )
        )
        #expect(
            withDependencies.contains(
                ".product(name: \"Algorithms\", package: \"swift-algorithms\")"
            )
        )
    }

    @Test
    func packageNameStripsGitSuffix() {
        #expect(
            ToolPackageLayout.packageName(from: "https://github.com/apple/swift-algorithms.git")
                == "swift-algorithms"
        )
        #expect(
            ToolPackageLayout.packageName(from: "https://github.com/apple/swift-nio")
                == "swift-nio"
        )
    }

    @Test
    func customAgentPromptProjectModeRequestsDependenciesViaSidecar() {
        let singleFile = CustomCodingAgentPrompt.compose(
            userPrompt: "Make a thing",
            displayName: "Sample App",
            executableName: "SampleApp",
            appKind: .window,
            sandboxEnabled: false,
            attachments: []
        )
        #expect(!singleFile.contains("package-request.json"))

        let project = CustomCodingAgentPrompt.compose(
            userPrompt: "Make a thing",
            displayName: "Sample App",
            executableName: "SampleApp",
            appKind: .window,
            sandboxEnabled: false,
            attachments: [],
            projectMode: true
        )
        #expect(project.contains("package-request.json"))
        #expect(project.contains("do NOT edit Package.swift"))
    }

    @Test
    func codexPromptProjectModeRequestsDependenciesViaSidecar() {
        let request = CodexAgentRequest(
            packageRootURL: URL(fileURLWithPath: "/tmp/sample"),
            executableName: "SampleApp",
            displayName: "Sample App",
            appKind: .window,
            sandboxEnabled: false,
            userPrompt: "Make a thing",
            modelIdentifier: "gpt-5-codex",
            modelFamily: .openAI,
            contextWindowTokens: nil,
            reasoningEffort: .medium,
            authentication: .chatGPTLogin,
            supportsImageInput: false,
            onEvent: { _ in }
        )
        let workspace = URL(fileURLWithPath: "/tmp/sample")

        let singleFile = CodexAgentClient.prompt(for: request, temporaryWorkspaceURL: workspace)
        #expect(!singleFile.contains("package-request.json"))

        var projectRequest = request
        projectRequest.projectMode = true
        let project = CodexAgentClient.prompt(
            for: projectRequest,
            temporaryWorkspaceURL: workspace
        )
        #expect(project.contains("package-request.json"))
        #expect(project.contains("do NOT edit Package.swift"))
    }
}
