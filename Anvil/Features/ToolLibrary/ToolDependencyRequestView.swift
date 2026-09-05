import SwiftData
import SwiftUI

/// Allow/reject review for Package.swift dependencies a coding agent
/// requested while building an app in project mode.
struct ToolDependencyRequestView: View {
    let tool: Tool
    let store: ToolLibraryStore

    @Environment(InferenceStore.self) private var inferenceStore
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @State private var requests: [ToolPackageDependencyRequest] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Dependency Request")
                .font(.headline)
            Text("\(tool.name) wants to add these Swift packages:")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            List {
                ForEach(requests, id: \.package) { request in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(request.product)
                            .font(.body.bold())
                        Text(request.package)
                            .font(.caption.monospaced())
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                        Text("Version \(request.from) or later")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 4)
                }
            }
            .listStyle(.inset)
            .frame(minHeight: 120)

            Text(
                "Allowed packages are fetched from the network on every build of this app. Rejecting sends the agent back to revise the app without them."
            )
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Button("Reject") {
                    store.rejectDependencyRequests(tool, in: modelContext)
                    dismiss()
                }
                Spacer()
                Button("Allow and Build") {
                    store.allowDependencyRequests(
                        tool,
                        modelContext: modelContext,
                        inferenceStore: inferenceStore
                    )
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(minWidth: 480, minHeight: 340)
        .onAppear {
            requests = store.pendingDependencyRequests(for: tool)
        }
    }
}
