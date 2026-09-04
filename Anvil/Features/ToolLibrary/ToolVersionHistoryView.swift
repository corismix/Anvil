import SwiftData
import SwiftUI

/// Per-app version history backed by the tool package's git repo.
struct ToolVersionHistoryView: View {
    let tool: Tool
    let store: ToolLibraryStore

    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var versions: [ToolGitCommit] = []
    @State private var diffSheet: DiffPresentation?

    private struct DiffPresentation: Identifiable {
        let sha: String
        let title: String
        let diff: String

        var id: String { sha }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Version History")
                .font(.headline)
            Text(tool.name)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            if versions.isEmpty {
                ContentUnavailableView(
                    "No Versions Yet",
                    systemImage: "clock.arrow.circlepath",
                    description: Text(
                        "Versions are recorded each time this app is generated or edited."
                    )
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(versions, id: \.sha) { version in
                        versionRow(version, isCurrent: version.sha == versions.first?.sha)
                    }
                }
                .listStyle(.inset)
            }

            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 520, minHeight: 420)
        .onAppear {
            versions = store.versionHistory(for: tool)
        }
        .sheet(item: $diffSheet) { presentation in
            diffView(presentation)
        }
    }

    @ViewBuilder
    private func versionRow(_ version: ToolGitCommit, isCurrent: Bool) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(version.subject)
                    .font(.body)
                    .lineLimit(2)
                Spacer()
                if isCurrent {
                    Text("Current")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            HStack(spacing: 8) {
                Text(version.date, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(String(version.sha.prefix(7)))
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
            }
            if !isCurrent {
                HStack(spacing: 12) {
                    Button("Restore") {
                        restore(version)
                    }
                    .disabled(store.restoringToolID == tool.id)
                    Button("Compare with Current") {
                        diffSheet = DiffPresentation(
                            sha: version.sha,
                            title: version.subject,
                            diff: store.versionDiff(for: tool, sha: version.sha)
                        )
                    }
                }
                .font(.callout)
            }
        }
        .padding(.vertical, 4)
    }

    private func restore(_ version: ToolGitCommit) {
        Task {
            await store.restoreVersion(tool, sha: version.sha, in: modelContext)
            versions = store.versionHistory(for: tool)
        }
    }

    @ViewBuilder
    private func diffView(_ presentation: DiffPresentation) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Changes Since This Version")
                .font(.headline)
            Text(presentation.title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            ScrollView {
                Text(presentation.diff.isEmpty ? "No differences." : presentation.diff)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8)
            }
            .background(Color(nsColor: .textBackgroundColor))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            HStack {
                Spacer()
                Button("Done") { diffSheet = nil }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 640, minHeight: 480)
    }
}
