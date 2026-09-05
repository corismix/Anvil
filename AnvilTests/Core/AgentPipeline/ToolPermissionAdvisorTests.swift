import Foundation
import Testing
@testable import Anvil

struct ToolPermissionAdvisorTests {
    @Test
    func networkSourceWithoutInternetPermissionAdvisesOutgoingConnections() {
        let advisories = ToolPermissionAdvisor.advisories(
            source: "import SwiftUI\nlet session = URLSession.shared",
            sandboxEnabled: true,
            sandboxPermissions: GeneratedAppSandboxPermissions([.userSelectedFiles]),
            resourcePermissions: .none
        )
        #expect(advisories.map(\.permissionName) == ["Internet access"])
        #expect(advisories.first?.matchedMarkers == ["URLSession"])
    }

    @Test
    func grantedPermissionProducesNoAdvisory() {
        let advisories = ToolPermissionAdvisor.advisories(
            source: "let session = URLSession.shared\nlet panel = NSOpenPanel()",
            sandboxEnabled: true,
            sandboxPermissions: .default,
            resourcePermissions: .none
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func resourcePermissionsAreAdvisedRegardlessOfSandbox() {
        let source = "let manager = CLLocationManager()\nlet store = CNContactStore()"
        let advisories = ToolPermissionAdvisor.advisories(
            source: source,
            sandboxEnabled: false,
            sandboxPermissions: .default,
            resourcePermissions: .none
        )
        #expect(advisories.map(\.permissionName) == ["Location", "Contacts"])
    }

    @Test
    func sandboxPermissionsAreSkippedWhenSandboxIsDisabled() {
        let advisories = ToolPermissionAdvisor.advisories(
            source: "let session = URLSession.shared\nlet listener = NWListener(using: .tcp)",
            sandboxEnabled: false,
            sandboxPermissions: GeneratedAppSandboxPermissions([]),
            resourcePermissions: .none
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func cameraAndMicrophoneMarkersAreDistinct() {
        let advisories = ToolPermissionAdvisor.advisories(
            source: "let session = AVCaptureSession()",
            sandboxEnabled: true,
            sandboxPermissions: .default,
            resourcePermissions: .none
        )
        #expect(advisories.map(\.permissionName) == ["Camera"])
    }

    @Test
    func emptySourceProducesNoAdvisory() {
        let advisories = ToolPermissionAdvisor.advisories(
            source: "  \n",
            sandboxEnabled: true,
            sandboxPermissions: GeneratedAppSandboxPermissions([]),
            resourcePermissions: .none
        )
        #expect(advisories.isEmpty)
    }

    @Test
    func summaryJoinsPermissionNames() {
        let summary = ToolPermissionAdvisor.summary([
            ToolPermissionAdvisory(permissionName: "Camera", matchedMarkers: ["AVCaptureSession"]),
            ToolPermissionAdvisory(permissionName: "Location", matchedMarkers: ["CLLocationManager"]),
        ])
        #expect(summary == "May need permission: Camera, Location")
        #expect(ToolPermissionAdvisor.summary([]) == nil)
    }
}
