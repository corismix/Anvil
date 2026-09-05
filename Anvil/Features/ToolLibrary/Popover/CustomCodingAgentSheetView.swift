import SwiftUI

struct AddCustomCodingAgentSheetView: View {
    @Environment(InferenceStore.self) private var inferenceStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CustomCodingAgentStore
    @State private var draft = CustomCodingAgentPreset.claudeCode.agent
    @State private var errorMessage: String?
    @State private var selectedPreset = CustomCodingAgentPreset.claudeCode

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Add Coding Agent")
                .font(.headline)

            field("Preset") {
                Picker(
                    "Preset",
                    selection: Binding(
                        get: { selectedPreset },
                        set: { preset in
                            selectedPreset = preset
                            applyPreset(preset)
                        }
                    )
                ) {
                    ForEach(CustomCodingAgentPreset.allCases) { preset in
                        Text(preset.displayName).tag(preset)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }

            CustomCodingAgentEditorFields(
                draft: $draft,
                errorMessage: errorMessage,
                validate: store.validate
            )

            Label(
                "Anvil doesn't manage your custom agent's active model or installation. A selected Anvil model is still required to generate app metadata.",
                systemImage: "exclamationmark.triangle.fill"
            )
            .font(.caption)
            .foregroundStyle(.orange)
            .lineLimit(nil)
            .fixedSize(horizontal: false, vertical: true)

            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(18)
        .frame(width: 390)
    }

    private func applyPreset(_ preset: CustomCodingAgentPreset) {
        let replacement = preset.agent
        draft = CustomCodingAgent(
            id: draft.id,
            name: replacement.name,
            command: replacement.command,
            promptDelivery: replacement.promptDelivery
        )
        errorMessage = nil
    }

    private func save() {
        do {
            let saved = try store.save(draft)
            store.selectedAgentID = saved.id
            inferenceStore.generationPreferences.codingAgentPreference = .custom
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
            content()
        }
    }
}

struct ManageCustomCodingAgentsSheetView: View {
    @Environment(InferenceStore.self) private var inferenceStore
    @Environment(\.dismiss) private var dismiss
    @Bindable var store: CustomCodingAgentStore
    @State private var draft: CustomCodingAgent?
    @State private var selectedID: UUID?
    @State private var errorMessage: String?
    @State private var isConfirmingRemoval = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Manage Coding Agents")
                .font(.headline)

            if let draft {
                field("Agent") {
                    Picker("Agent", selection: $selectedID) {
                        ForEach(store.agents) { agent in
                            Text(agent.name).tag(Optional(agent.id))
                        }
                    }
                    .labelsHidden()
                    .pickerStyle(.menu)
                }

                CustomCodingAgentEditorFields(
                    draft: draftBinding(fallback: draft),
                    errorMessage: errorMessage,
                    validate: store.validate
                )
                .id(draft.id)
            } else {
                ContentUnavailableView(
                    "No Custom Agents",
                    systemImage: "terminal",
                    description: Text("Add a coding agent before managing one.")
                )
            }

            HStack {
                Button("Remove", role: .destructive) {
                    isConfirmingRemoval = true
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .disabled(draft == nil)

                Spacer()

                Button("Cancel", role: .cancel) { dismiss() }
                Button("Save") { save() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.defaultAction)
                    .disabled(draft == nil)
            }
        }
        .padding(18)
        .frame(width: 390)
        .onAppear { selectInitialAgent() }
        .onChange(of: selectedID) { _, _ in loadSelectedDraft() }
        .confirmationDialog(
            "Remove \(draft?.name ?? "Coding Agent")?",
            isPresented: $isConfirmingRemoval
        ) {
            Button("Remove Agent", role: .destructive) { removeSelectedAgent() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes the coding agent configuration from Anvil.")
        }
    }

    private func selectInitialAgent() {
        let persistedSelection = store.selectedAgentID.flatMap { selectedID in
            store.agents.contains(where: { $0.id == selectedID }) ? selectedID : nil
        }
        selectedID = persistedSelection ?? store.agents.first?.id
        loadSelectedDraft()
    }

    private func loadSelectedDraft() {
        draft = selectedID.flatMap { id in store.agents.first { $0.id == id } }
        errorMessage = nil
    }

    private func draftBinding(fallback: CustomCodingAgent) -> Binding<CustomCodingAgent> {
        Binding(
            get: { draft ?? fallback },
            set: { draft = $0 }
        )
    }

    private func save() {
        guard let draft else { return }
        do {
            let saved = try store.save(draft)
            store.selectedAgentID = saved.id
            inferenceStore.generationPreferences.codingAgentPreference = .custom
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func removeSelectedAgent() {
        guard let selectedID else { return }
        let removedSelectedAgent = store.selectedAgentID == selectedID
        store.delete(id: selectedID)
        if removedSelectedAgent {
            inferenceStore.generationPreferences.codingAgentPreference = .automatic
        }
        dismiss()
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
            content()
        }
    }
}

private func optionalText(_ binding: Binding<String?>) -> Binding<String> {
    Binding(
        get: { binding.wrappedValue ?? "" },
        set: { binding.wrappedValue = $0.isEmpty ? nil : $0 }
    )
}

private struct CustomCodingAgentEditorFields: View {
    @Binding var draft: CustomCodingAgent
    let errorMessage: String?
    let validate: (CustomCodingAgent) throws -> CustomCodingAgent
    @State private var testStore = CustomCodingAgentTestStore()

    private var structuredLaunchEnabled: Binding<Bool> {
        Binding(
            get: { draft.structuredLaunch != nil },
            set: { enabled in
                if enabled {
                    draft.structuredLaunch = StructuredAgentLaunchResolver
                        .parseLegacyCommand(draft.command) ?? StructuredAgentLaunch()
                } else {
                    draft.structuredLaunch = nil
                }
            }
        )
    }

    private func structuredText(
        _ keyPath: WritableKeyPath<StructuredAgentLaunch, String>
    ) -> Binding<String> {
        Binding(
            get: { draft.structuredLaunch?[keyPath: keyPath] ?? "" },
            set: { draft.structuredLaunch?[keyPath: keyPath] = $0 }
        )
    }

    private func structuredLines(
        _ keyPath: WritableKeyPath<StructuredAgentLaunch, [String]>
    ) -> Binding<String> {
        Binding(
            get: { draft.structuredLaunch?[keyPath: keyPath].joined(separator: "\n") ?? "" },
            set: { newValue in
                draft.structuredLaunch?[keyPath: keyPath] = newValue
                    .split(separator: "\n", omittingEmptySubsequences: true)
                    .map(String.init)
            }
        )
    }

    private var structuredEnvironment: Binding<String> {
        Binding(
            get: {
                (draft.structuredLaunch?.environment ?? [:])
                    .sorted { $0.key < $1.key }
                    .map { "\($0.key)=\($0.value)" }
                    .joined(separator: "\n")
            },
            set: { newValue in
                var environment: [String: String] = [:]
                for line in newValue.split(separator: "\n", omittingEmptySubsequences: true) {
                    guard let separator = line.firstIndex(of: "=") else { continue }
                    let key = String(line[line.startIndex..<separator])
                    let value = String(line[line.index(after: separator)...])
                    guard !key.isEmpty else { continue }
                    environment[key] = value
                }
                draft.structuredLaunch?.environment = environment
            }
        )
    }

    private var structuredTimeout: Binding<String> {
        Binding(
            get: { String(draft.structuredLaunch?.timeoutSeconds ?? 0) },
            set: { newValue in
                draft.structuredLaunch?.timeoutSeconds = Int(newValue) ?? 0
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            field("Name") {
                TextField("Agent name", text: $draft.name)
            }

            if let adapter = draft.nativeAdapter {
                field("Model") {
                    TextField(
                        adapter.defaultModel.isEmpty ? "CLI default" : adapter.defaultModel,
                        text: optionalText($draft.adapterModel)
                    )
                    .font(.system(.body, design: .monospaced))
                }
                field("Mode") {
                    TextField(
                        "Adapter default",
                        text: optionalText($draft.adapterMode)
                    )
                    .font(.system(.body, design: .monospaced))
                }
            } else {
                Picker("Launch", selection: structuredLaunchEnabled) {
                    Text("Structured").tag(true)
                    Text("Shell command (legacy)").tag(false)
                }
                .labelsHidden()

                if draft.structuredLaunch != nil {
                    field("Executable") {
                        TextField(
                            "/opt/homebrew/bin/agent or name on PATH",
                            text: structuredText(\.executable)
                        )
                        .font(.system(.body, design: .monospaced))
                    }

                    field("Arguments (one per line)") {
                        TextField(
                            "--prompt {{prompt}}",
                            text: structuredLines(\.arguments),
                            axis: .vertical
                        )
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...5)
                        Text(
                            "With no {{prompt}} anywhere, the prompt is sent on standard input."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }

                    field("Environment (KEY=VALUE, one per line)") {
                        TextField(
                            "API_URL=https://example.test",
                            text: structuredEnvironment,
                            axis: .vertical
                        )
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(2...4)
                    }

                    field("Timeout (seconds, 0 = none)") {
                        TextField("0", text: structuredTimeout)
                            .font(.system(.body, design: .monospaced))
                    }
                } else {
                    field("Command") {
                        TextField(
                            CustomCodingAgentPreset.openCode.agent.command,
                            text: $draft.command,
                            axis: .vertical
                        )
                        .font(.system(.body, design: .monospaced))
                        .lineLimit(3...6)
                    }

                    field("Send Prompt") {
                        Picker("Send Prompt", selection: $draft.promptDelivery) {
                            Text("Replace {{prompt}}").tag(CustomCodingAgent.PromptDelivery.placeholder)
                            Text("Standard input").tag(CustomCodingAgent.PromptDelivery.standardInput)
                        }
                        .labelsHidden()
                    }

                    if StructuredAgentLaunchResolver.parseLegacyCommand(draft.command) != nil {
                        Button("Convert to structured launch") {
                            draft.structuredLaunch = StructuredAgentLaunchResolver
                                .parseLegacyCommand(draft.command)
                        }
                        .font(.caption)
                    }
                }
            }

            field("Test Agent") {
                VStack(alignment: .leading, spacing: 8) {
                    Button {
                        testStore.run(agent: draft, validate: validate)
                    } label: {
                        HStack(spacing: 6) {
                            if testStore.isRunning {
                                ProgressView()
                                    .controlSize(.small)
                            }
                            Text(testStore.isRunning ? "Testing…" : "Test")
                        }
                    }
                    .disabled(testStore.isRunning)

                    if let output = testStore.output {
                        ScrollView {
                            Text(output)
                                .font(.system(.caption, design: .monospaced))
                                .textSelection(.enabled)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .frame(height: 82)
                        .padding(8)
                        .background(
                            .quaternary.opacity(0.3),
                            in: RoundedRectangle(cornerRadius: 7)
                        )
                        .overlay {
                            RoundedRectangle(cornerRadius: 7)
                                .strokeBorder(.secondary.opacity(0.15))
                        }
                    }

                    if let testError = testStore.errorMessage {
                        Text(testError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                }
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onChange(of: draft) { _, _ in testStore.reset() }
        .onDisappear { testStore.reset() }
    }

    private func field<Content: View>(
        _ label: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.medium))
            content()
        }
    }
}
