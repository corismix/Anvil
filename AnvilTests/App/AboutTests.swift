import AcknowList
import Foundation
import Testing
@testable import Anvil

struct AboutTests {
    @Test
    func aboutMetadataUsesBundleInfo() {
        let metadata = AnvilAboutMetadata(
            infoDictionary: [
                "CFBundleDisplayName": "Test Anvil",
                "CFBundleName": "Fallback Name",
                "CFBundleShortVersionString": "2.3",
                "CFBundleVersion": "45",
                "NSHumanReadableCopyright": "Copyright © 2026 Jade Westover"
            ]
        )

        #expect(metadata.applicationName == "Test Anvil")
        #expect(metadata.applicationVersion == "2.3")
        #expect(metadata.versionText == "Version 2.3")
        #expect(metadata.copyright == "Copyright © 2026 Jade Westover")
        #expect(metadata.licenseSummary == "Licensed under GNU GPLv3")
        #expect(metadata.sourceCodeURL.absoluteString == "https://github.com/corismix/Ironsmith")
    }

    @Test
    func aboutMetadataFallsBackGracefully() {
        let metadata = AnvilAboutMetadata(infoDictionary: [:])

        #expect(metadata.applicationName == "Anvil")
        #expect(metadata.applicationVersion == nil)
        #expect(metadata.versionText == nil)
        #expect(metadata.copyright == AnvilAboutMetadata.fallbackCopyright)
        #expect(metadata.licenseSummary == "Licensed under GNU GPLv3")
    }

    @Test
    func aboutMetadataFormatsVersionTextWithoutBuild() {
        let metadata = AnvilAboutMetadata(
            infoDictionary: [
                "CFBundleName": "Anvil",
                "CFBundleShortVersionString": "2.3"
            ]
        )

        #expect(metadata.applicationVersion == "2.3")
        #expect(metadata.versionText == "Version 2.3")
    }

    @Test
    func aboutMetadataDoesNotDisplayBuildNumber() {
        let metadata = AnvilAboutMetadata(
            infoDictionary: [
                "CFBundleName": "Anvil",
                "CFBundleVersion": "45"
            ]
        )

        #expect(metadata.applicationVersion == nil)
        #expect(metadata.versionText == nil)
    }

    @Test
    func gplResourceTextExistsInAppResources() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let gplResourceURL = repositoryRootURL
            .appendingPathComponent("Anvil/Resources/GPLv3.txt")

        let text = AnvilLegalDocument.gplv3.text(resourceURL: gplResourceURL)

        #expect(text.contains("GNU GENERAL PUBLIC LICENSE"))
        #expect(text.contains("Version 3, 29 June 2007"))
    }

    @Test
    func codexLegalResourcesExistAndProduceAcknowledgement() throws {
        let testFileURL = URL(fileURLWithPath: #filePath)
        let repositoryRootURL = testFileURL
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let licensesURL = repositoryRootURL
            .appendingPathComponent("Anvil/Resources/ThirdPartyLicenses", isDirectory: true)
        let licenseText = AnvilLegalDocument.codexApache2.text(
            resourceURL: licensesURL.appendingPathComponent("OpenAI-Codex-Apache-2.0.txt")
        )
        let noticeText = AnvilLegalDocument.codexNotice.text(
            resourceURL: licensesURL.appendingPathComponent("OpenAI-Codex-NOTICE.txt")
        )
        let acknowledgement = AnvilLicenseAcknowledgements.codexAcknowledgement(
            licenseText: licenseText,
            noticeText: noticeText
        )

        #expect(licenseText.contains("Apache License"))
        #expect(licenseText.contains("Version 2.0, January 2004"))
        #expect(noticeText.contains("OpenAI Codex"))
        #expect(acknowledgement.title == "OpenAI Codex")
        #expect(acknowledgement.license == "Apache 2.0")
        #expect(acknowledgement.text?.contains("Ratatui") == true)
        #expect(acknowledgement.repository?.absoluteString == "https://github.com/openai/codex")
    }
}
