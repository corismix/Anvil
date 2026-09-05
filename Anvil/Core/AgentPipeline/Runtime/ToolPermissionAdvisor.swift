import Foundation

/// One advisory: a permission the generated source appears to use but was not granted.
struct ToolPermissionAdvisory: Equatable, Sendable {
    let permissionName: String
    let matchedMarkers: [String]
}

/// Deterministic post-build permission scan. Matches API markers in the
/// generated source against the permissions the app was granted and reports
/// the gaps. Advisory only: it never blocks generation and never changes
/// permissions.
nonisolated enum ToolPermissionAdvisor {
    private struct PermissionRule {
        let permissionName: String
        let markers: [String]
        let isGranted: @Sendable (GeneratedAppSandboxPermissions, GeneratedAppResourcePermissions) -> Bool
        let requiresSandbox: Bool
    }

    private static let sandboxRules: [PermissionRule] = [
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.outgoingConnections.displayName,
            markers: ["URLSession", "NSURLSession", "NWConnection", "NWBrowser"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.outgoingConnections) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.incomingConnections.displayName,
            markers: ["NWListener"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.incomingConnections) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.userSelectedFiles.displayName,
            markers: ["NSOpenPanel", "NSSavePanel"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.userSelectedFiles) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.downloadsFolder.displayName,
            markers: [".downloadsDirectory"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.downloadsFolder) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.picturesFolder.displayName,
            markers: [".picturesDirectory"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.picturesFolder) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.musicFolder.displayName,
            markers: [".musicDirectory"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.musicFolder) },
            requiresSandbox: true
        ),
        PermissionRule(
            permissionName: GeneratedAppSandboxPermission.moviesFolder.displayName,
            markers: [".moviesDirectory"],
            isGranted: { sandbox, _ in sandbox.enabled.contains(.moviesFolder) },
            requiresSandbox: true
        ),
    ]

    private static let resourceRules: [PermissionRule] = [
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.microphone.displayName,
            markers: ["AVAudioEngine", "AVAudioRecorder", "SFSpeechRecognizer", "AVCaptureDevice.default(for: .audio"],
            isGranted: { _, resource in resource.enabled.contains(.microphone) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.camera.displayName,
            markers: ["AVCaptureSession", "AVCapturePhotoOutput", "AVCaptureDevice.default(for: .video"],
            isGranted: { _, resource in resource.enabled.contains(.camera) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.location.displayName,
            markers: ["CLLocationManager"],
            isGranted: { _, resource in resource.enabled.contains(.location) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.contacts.displayName,
            markers: ["CNContactStore"],
            isGranted: { _, resource in resource.enabled.contains(.contacts) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.calendar.displayName,
            markers: ["EKEventStore"],
            isGranted: { _, resource in resource.enabled.contains(.calendar) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.photoLibrary.displayName,
            markers: ["PHPhotoLibrary", "PHAsset"],
            isGranted: { _, resource in resource.enabled.contains(.photoLibrary) },
            requiresSandbox: false
        ),
        PermissionRule(
            permissionName: GeneratedAppResourcePermission.appleEvents.displayName,
            markers: ["NSAppleScript", "AppleEventManager"],
            isGranted: { _, resource in resource.enabled.contains(.appleEvents) },
            requiresSandbox: false
        ),
    ]

    static func advisories(
        source: String,
        sandboxEnabled: Bool,
        sandboxPermissions: GeneratedAppSandboxPermissions,
        resourcePermissions: GeneratedAppResourcePermissions
    ) -> [ToolPermissionAdvisory] {
        guard !source.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        var result: [ToolPermissionAdvisory] = []
        for rule in sandboxRules + resourceRules {
            if rule.requiresSandbox && !sandboxEnabled { continue }
            if rule.isGranted(sandboxPermissions, resourcePermissions) { continue }
            let matched = rule.markers.filter { source.contains($0) }
            if !matched.isEmpty {
                result.append(
                    ToolPermissionAdvisory(permissionName: rule.permissionName, matchedMarkers: matched)
                )
            }
        }
        return result
    }

    /// Reads every Swift source file in the package and returns the advisories
    /// for it. Used after a successful build.
    static func advisories(
        layout: ToolPackageLayout,
        sandboxEnabled: Bool,
        sandboxPermissions: GeneratedAppSandboxPermissions,
        resourcePermissions: GeneratedAppResourcePermissions
    ) -> [ToolPermissionAdvisory] {
        let fileManager = FileManager.default
        guard let enumerator = fileManager.enumerator(
            at: layout.sourceDirectoryURL,
            includingPropertiesForKeys: nil
        ) else { return [] }
        var source = ""
        for case let url as URL in enumerator where url.pathExtension == "swift" {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            source += text + "\n"
        }
        return advisories(
            source: source,
            sandboxEnabled: sandboxEnabled,
            sandboxPermissions: sandboxPermissions,
            resourcePermissions: resourcePermissions
        )
    }

    static func summary(_ advisories: [ToolPermissionAdvisory]) -> String? {
        guard !advisories.isEmpty else { return nil }
        let names = advisories.map(\.permissionName).joined(separator: ", ")
        return "May need permission: \(names)"
    }
}
