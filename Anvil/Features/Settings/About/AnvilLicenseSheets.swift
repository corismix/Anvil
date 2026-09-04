import AcknowList
import SwiftUI

enum AnvilLicenseAcknowledgements {
    static func appAcknowledgement(
        metadata: AnvilAboutMetadata = .current(),
        document: AnvilLegalDocument = .gplv3
    ) -> Acknow {
        Acknow(
            title: metadata.applicationName,
            text: document.text(),
            license: "GNU GPLv3",
            repository: metadata.sourceCodeURL
        )
    }

    static func all(
        metadata: AnvilAboutMetadata = .current(),
        document: AnvilLegalDocument = .gplv3,
        codexLicenseText: String = AnvilLegalDocument.codexApache2.text(),
        codexNoticeText: String = AnvilLegalDocument.codexNotice.text()
    ) -> [Acknow] {
        [
            appAcknowledgement(metadata: metadata, document: document),
            codexAcknowledgement(
                licenseText: codexLicenseText,
                noticeText: codexNoticeText
            ),
        ]
            + (AcknowParser.defaultAcknowList()?.acknowledgements ?? [])
    }

    static func codexAcknowledgement(
        licenseText: String = AnvilLegalDocument.codexApache2.text(),
        noticeText: String = AnvilLegalDocument.codexNotice.text()
    ) -> Acknow {
        Acknow(
            title: "OpenAI Codex",
            text: "\(licenseText)\n\nNOTICE\n\n\(noticeText)",
            license: "Apache 2.0",
            repository: URL(string: "https://github.com/openai/codex")!
        )
    }
}

struct AnvilLicensesSheet: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            AcknowListSwiftUIView(acknowledgements: AnvilLicenseAcknowledgements.all())
                .navigationTitle("Licenses")
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                Spacer()
                Button("Close") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(20)
            .background(.bar)
        }
        .frame(minWidth: 520, minHeight: 460)
    }
}
