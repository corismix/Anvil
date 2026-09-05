import SwiftUI

struct ProviderEditorSheetView: View {
    @Environment(InferenceStore.self) private var inferenceStore
    let provider: ProviderConfig
    @Environment(\.dismiss) private var dismiss

    @State private var apiKey = ""
    @State private var displayName = ""
    @State private var baseURLString = ""
    @State private var openAICompatibleAPIVariant: OpenAICompatibleAPIVariant = .chatCompletions
    @State private var isConfirmingDelete = false
    @State private var isSigningInToChatGPT = false
    @State private var isSigningOutOfChatGPT = false
    let onNestedSheetPresentationChange: (Bool) -> Void

    private var isCustomOpenAICompatible: Bool {
        provider.kind == .customOpenAICompatible
    }

    private var isOpenAI: Bool {
        provider.kind == .openAI
    }

    private var isOllama: Bool {
        provider.kind == .ollama
    }

    private var usesEditableConnection: Bool {
        isCustomOpenAICompatible || isOllama
    }

    private var isOpenCodeZenEndpoint: Bool {
        let trimmed = baseURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed) else {
            return false
        }
        return OpenCodeZenCatalog.isZenEndpoint(url)
    }

    init(
        provider: ProviderConfig,
        onNestedSheetPresentationChange: @escaping (Bool) -> Void = { _ in }
    ) {
        self.provider = provider
        self.onNestedSheetPresentationChange = onNestedSheetPresentationChange
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    providerSummaryRow
                }
                if provider.kind == .local {
                    Section {
                        LocalModelManagementView(provider: provider)
                    } header: {
                        Text("AI Models")
                    }
                } else if isOpenAI {
                    openAIAuthenticationSections
                } else {
                    if usesEditableConnection {
                        Section {
                            if isCustomOpenAICompatible {
                                TextField("Display Name", text: $displayName, prompt: Text("LM Studio"))
                            }
                            TextField(
                                isOllama ? "Server URL" : "Base URL",
                                text: $baseURLString,
                                prompt: Text(isOllama ? "http://localhost:11434" : "http://localhost:1234/v1")
                            )
                            if isCustomOpenAICompatible {
                                Picker("API", selection: $openAICompatibleAPIVariant) {
                                    ForEach(OpenAICompatibleAPIVariant.allCases) { variant in
                                        Text(variant.displayName).tag(variant)
                                    }
                                }
                                .pickerStyle(.segmented)
                                if isOpenCodeZenEndpoint {
                                    Text(
                                        "OpenCode Zen detected. Each model's API protocol is chosen automatically; this setting only applies to models Anvil doesn't recognize."
                                    )
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                }
                            }
                        } header: {
                            Text("Connection")
                        }
                    }

                    Section {
                        SecureField(
                            "API Key",
                            text: $apiKey,
                            prompt: Text(usesEditableConnection ? "Optional" : "Required")
                        )
                    } header: {
                        Text("Authentication")
                    }

                    if isOllama {
                        Section {
                            OllamaModelManagementView(provider: provider)
                        } header: {
                            Text("Recommended AI Models")
                        }
                    }
                }
            }
            .formStyle(.grouped)
            .padding(20)
        }
        .safeAreaInset(edge: .bottom) {
            HStack {
                if provider.isRemovable {
                    Button("Delete Provider", role: .destructive) {
                        isConfirmingDelete = true
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }

                Spacer()

                Button("Close") {
                    dismiss()
                }

                if provider.kind != .local {
                    Button("Save") {
                        Task {
                            let didSave = await inferenceStore.saveProviderEdits(
                                provider: provider,
                                apiKey: apiKey,
                                displayName: isCustomOpenAICompatible ? displayName : nil,
                                baseURLString: usesEditableConnection ? baseURLString : nil,
                                openAICompatibleAPIVariant: isCustomOpenAICompatible
                                    ? openAICompatibleAPIVariant
                                    : nil
                            )
                            await MainActor.run {
                                if didSave {
                                    dismiss()
                                }
                            }
                        }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(isSaveDisabled)
                }
            }
            .padding(20)
            .background(.bar)
        }
        .frame(minWidth: 540, minHeight: 430)
        .onAppear {
            apiKey = inferenceStore.apiKey(for: provider)
            displayName = provider.displayName
            baseURLString = provider.baseURLString
            openAICompatibleAPIVariant = provider.openAICompatibleAPIVariant
            if isOpenAI {
                inferenceStore.refreshOpenAICodexCredential()
            }
        }
        .onDisappear {
            onNestedSheetPresentationChange(false)
        }
        .textFieldStyle(.roundedBorder)
        .confirmationDialog(
            "Delete \(provider.displayName)?",
            isPresented: $isConfirmingDelete
        ) {
            Button("Delete Provider", role: .destructive) {
                Task {
                    await inferenceStore.removeProvider(provider)
                    await MainActor.run {
                        dismiss()
                    }
                }
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This removes \(provider.displayName) and all of its AI models from Anvil.")
        }
    }

    private var providerSummaryRow: some View {
        ProviderSummaryRowView(provider: provider, logoSize: 34, subtitleFont: .subheadline)
            .padding(.vertical, 2)
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { inferenceStore.presentedErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    inferenceStore.clearPresentedError()
                }
            }
        )
    }

    @ViewBuilder
    private var openAIAuthenticationSections: some View {
        Section {
            SecureField("API Key", text: $apiKey, prompt: Text("Optional"))
        } header: {
            Text("API Key")
        }

        Section {
            HStack {
                LabeledContent("ChatGPT") {
                    Text(openAIChatGPTStatusText)
                        .foregroundStyle(inferenceStore.hasOpenAICodexCredential ? .primary : .secondary)
                }

                Spacer()

                if inferenceStore.hasOpenAICodexCredential {
                    Button(openAIChatGPTSignOutTitle) {
                        signOutOpenAIChatGPT()
                    }
                    .disabled(isSigningInToChatGPT || isSigningOutOfChatGPT)
                } else {
                    Button(openAIChatGPTSignInTitle) {
                        signInWithOpenAIChatGPT()
                    }
                    .disabled(isSigningInToChatGPT || isSigningOutOfChatGPT)
                }
            }
        } header: {
            Text("ChatGPT")
        }
    }

    private var openAIChatGPTStatusText: String {
        inferenceStore.openAICodexCredential?.statusText ?? "Not signed in"
    }

    private var openAIChatGPTSignInTitle: String {
        isSigningInToChatGPT ? "Signing In..." : "Sign In"
    }

    private var openAIChatGPTSignOutTitle: String {
        isSigningOutOfChatGPT ? "Signing Out..." : "Sign Out"
    }

    private func signInWithOpenAIChatGPT() {
        guard !isSigningInToChatGPT, !isSigningOutOfChatGPT else { return }

        isSigningInToChatGPT = true
        Task {
            let didSignIn = await inferenceStore.signInToOpenAIChatGPT()

            await MainActor.run {
                isSigningInToChatGPT = false
                if didSignIn {
                    inferenceStore.refreshOpenAICodexCredential()
                }
            }
        }
    }

    private func signOutOpenAIChatGPT() {
        guard !isSigningInToChatGPT, !isSigningOutOfChatGPT else { return }

        isSigningOutOfChatGPT = true
        Task {
            let didSignOut = await inferenceStore.signOutOpenAIChatGPT(provider: provider)
            await MainActor.run {
                isSigningOutOfChatGPT = false
                if didSignOut {
                    inferenceStore.refreshOpenAICodexCredential()
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        if isCustomOpenAICompatible {
            return displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                || baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        if isOllama {
            return baseURLString.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        return false
    }
}
