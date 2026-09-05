import Foundation
import SwiftData
import SwiftUI

private enum CustomCodingAgentSheet: String, Identifiable {
    case add
    case manage

    var id: String { rawValue }
}

struct ToolLibraryPopoverView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceStore.self) private var inferenceStore
    @Environment(AnvilRouteStore.self) private var routeStore
    @Environment(MenuBarPopoverPresentationStore.self) private var menuBarPopoverPresentationStore
    @Query(sort: \Tool.updatedAt, order: .reverse) private var tools: [Tool]
    @AppStorage(AnvilPreferenceKeys.showSandboxOverride) private var showSandboxOverride = false
    @AppStorage(AnvilPreferenceKeys.toolLibraryViewMode) private var viewModeRawValue =
        ToolLibraryViewMode.list.rawValue
    @AppStorage(AnvilPreferenceKeys.toolLibrarySortOrder) private var sortOrderRawValue =
        ToolLibrarySortOrder.latest.rawValue
    #if DEBUG
        @AppStorage(AnvilPreferenceKeys.debugAlwaysShowWelcomeOnboarding)
        private var debugAlwaysShowWelcomeOnboarding = false
        @AppStorage(AnvilPreferenceKeys.debugPopoverEmptyStateMode)
        private var debugPopoverEmptyStateModeRawValue = ToolLibraryDebugPopoverEmptyStateMode.off
            .rawValue
    #endif
    let appUpdateStore: AppUpdateStore
    private let welcomeOnboardingStore: WelcomeOnboardingStore
    @State private var toolLibraryStore = ToolLibraryStore()
    @State private var detailsEditor: ToolAppDetailsEditorStore
    @State private var toolPendingDeletion: Tool?
    @State private var hasCheckedWelcomeOnboarding = false
    @State private var isShowingWelcomeOnboarding = false
    @State private var isShowingModelPicker = false
    @State private var customCodingAgentSheet: CustomCodingAgentSheet?
    @State private var versionHistoryTool: Tool?
    @State private var isSearchPresented = false
    @State private var isPromptExpanded = false
    @State private var searchText = ""
    @FocusState private var isPromptFocused: Bool

    @MainActor
    init() {
        appUpdateStore = AppUpdateStore()
        welcomeOnboardingStore = WelcomeOnboardingStore()
        _detailsEditor = State(initialValue: ToolAppDetailsEditorStore())
    }

    @MainActor
    init(
        appUpdateStore: AppUpdateStore,
        welcomeOnboardingStore: WelcomeOnboardingStore? = nil,
        iconClient: ToolIconClient = .cachedOnly(),
        iconEditingClient: ToolIconEditingClient? = nil,
        iconBuildClient: ToolBuildClient? = nil
    ) {
        self.appUpdateStore = appUpdateStore
        self.welcomeOnboardingStore = welcomeOnboardingStore ?? WelcomeOnboardingStore()
        let buildClient = iconBuildClient ?? .live()
        _detailsEditor = State(
            initialValue: ToolAppDetailsEditorStore(
                iconClient: iconEditingClient,
                buildClient: buildClient
            )
        )
    }

    var body: some View {
        sheetContent
    }

    private var lifecycleContent: some View {
        popoverLayout
        .padding(16)
        .frame(width: 340, height: 500)
        .accessibilityIdentifier("tool-library-root")
        .task(id: restoreAvailabilityRefreshID) {
            await toolLibraryStore.refreshRestoreAvailability(for: tools)
        }
        .onAppear {
            handlePopoverAppear()
        }
        .onDisappear {
            handlePopoverClose()
        }
        .onChange(of: menuBarPopoverPresentationStore.showCount) { _, _ in
            handlePopoverShow()
        }
        .onChange(of: menuBarPopoverPresentationStore.closeCount) { _, _ in
            handlePopoverClose()
        }
        .task(id: inferenceStore.hasLoadedModels) {
            presentWelcomeOnboardingIfNeeded()
        }
        .task(id: runningApplicationsRefreshID) {
            await toolLibraryStore.refreshRunningApplications(for: tools)
        }
        .onChange(of: tools.map(\.id)) { _, _ in
            toolLibraryStore.syncSelection(with: tools, defaultSettings: defaultGenerationSettings)
            applyPendingToolLibraryRoute()
        }
        .onChange(of: defaultGenerationSettings) { _, settings in
            toolLibraryStore.initializeNextGenerationSettingsIfNeeded(settings)
        }
        .onChange(of: showSandboxOverride) { _, isEnabled in
            if !isEnabled {
                toolLibraryStore.sandboxEnabled = true
                toolLibraryStore.rememberCurrentGenerationSettingsForNextGeneration()
            }
        }
    }

    private var alertContent: some View {
        lifecycleContent
        .alert(
            "Anvil couldn’t finish",
            isPresented: toolLibraryErrorPresentedBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(toolLibraryStore.presentedErrorMessage ?? "")
        }
        .alert(
            "AI Model Unavailable",
            isPresented: modelFallbackPresentedBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inferenceStore.selectedModelFallbackMessage ?? "")
        }
        .alert(
            "Sign In Failed",
            isPresented: signInErrorPresentedBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inferenceStore.presentedErrorMessage ?? "")
        }
        .confirmationDialog(
            "Delete App?",
            isPresented: deleteConfirmationBinding
        ) {
            Button("Delete App", role: .destructive) {
                if let toolPendingDeletion {
                    toolLibraryStore.delete(toolPendingDeletion, in: modelContext)
                }
                toolPendingDeletion = nil
            }
            Button("Cancel", role: .cancel) {
                toolPendingDeletion = nil
            }
        } message: {
            Text(
                toolPendingDeletion.map { "Delete \($0.name)? This can't be undone." }
                    ?? "Delete this app? This can't be undone.")
        }
    }

    private var sheetContent: some View {
        @Bindable var detailsEditor = detailsEditor

        return alertContent
        .sheet(
            isPresented: $isShowingWelcomeOnboarding,
            onDismiss: dismissWelcomeOnboardingPresentation
        ) {
            AnvilWelcomeOnboardingSheetView(
                onComplete: completeWelcomeOnboarding
            )
        }
        .sheet(isPresented: $detailsEditor.isShowingSheet) {
            detailsEditorSheet
        }
        .sheet(isPresented: $isShowingModelPicker) {
            ModelPickerSheetView()
        }
        .sheet(item: $versionHistoryTool) { tool in
            ToolVersionHistoryView(tool: tool, store: toolLibraryStore)
                .environment(\.modelContext, modelContext)
        }
        .sheet(
            isPresented: Binding(
                get: { toolLibraryStore.dependencyApprovalToolID != nil },
                set: { isPresented in
                    if !isPresented {
                        toolLibraryStore.dependencyApprovalToolID = nil
                    }
                }
            )
        ) {
            if let id = toolLibraryStore.dependencyApprovalToolID,
                let tool = tools.first(where: { $0.id == id })
            {
                ToolDependencyRequestView(tool: tool, store: toolLibraryStore)
                    .environment(\.modelContext, modelContext)
            }
        }
        .sheet(item: $customCodingAgentSheet) { sheet in
            switch sheet {
            case .add:
                AddCustomCodingAgentSheetView(store: inferenceStore.customCodingAgents)
            case .manage:
                ManageCustomCodingAgentsSheetView(store: inferenceStore.customCodingAgents)
            }
        }
    }

    // The menu bar popover stays intentionally small: tool list first, prompt last.
    private var popoverLayout: some View {
        VStack(spacing: 14) {
            ToolLibraryPopoverHeaderView(
                isSearchPresented: $isSearchPresented,
                searchText: $searchText,
                viewMode: viewModeBinding,
                sortOrder: sortOrderBinding,
                appUpdateStore: appUpdateStore,
                isLoadingModels: !inferenceStore.hasLoadedModels && !shouldForceNoModels,
                onOpenSettings: {
                    routeStore.open(.settings(.root))
                }
            )

            if !isPromptExpanded {
                ScrollView {
                    toolCollectionContent
                }
                .scrollIndicators(.hidden)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.vertical, 14)
                .padding(.leading, 14)
                .padding(.trailing, 6)
                .background(.quaternary.opacity(0.28), in: RoundedRectangle(cornerRadius: 18))
                .transition(.opacity)
            }

            PromptComposerView(
                prompt: $toolLibraryStore.prompt,
                isExpanded: $isPromptExpanded,
                sandboxEnabled: sandboxEnabledBinding,
                appKindPreference: appKindPreferenceBinding,
                projectMode: projectModeBinding,
                sandboxPermissions: sandboxPermissionsBinding,
                resourcePermissions: resourcePermissionsBinding,
                codingAgentPreference: codingAgentPreferenceBinding,
                reasoningEffort: reasoningEffortBinding,
                placeholder: toolLibraryStore.promptPlaceholder,
                showsSandboxControl: showSandboxOverride,
                showsPermissionControls: !inferenceStore.generationPreferences
                    .automaticallySelectGeneratedAppPermissions,
                modelPickerTitle: composerModelPickerTitle,
                isModelPickerEnabled: isComposerModelPickerEnabled,
                isSubmitEnabled: canSubmitPrompt,
                isSubmitting: toolLibraryStore.isGenerating,
                isCodexAgentSupported: inferenceStore.selectedModelSupportsCodingAgentPreference(.codex),
                customCodingAgents: inferenceStore.customCodingAgents.agents,
                selectedCustomCodingAgentID: inferenceStore.customCodingAgents.selectedAgentID,
                showsAttachmentControls: selectedModelCanUseCodexAttachments
                    || inferenceStore.generationPreferences.codingAgentPreference == .custom,
                supportsAttachments: selectedModelSupportsAttachments,
                attachments: toolLibraryStore.attachments,
                supportedReasoningEfforts: inferenceStore.selectedModelSupportedReasoningEfforts,
                isPromptFocused: $isPromptFocused,
                onChooseModel: {
                    isShowingModelPicker = true
                },
                onSubmit: {
                    requestPromptSubmission()
                },
                onCancel: {
                    toolLibraryStore.cancelGeneration()
                },
                onAddAttachments: { urls in
                    guard toolLibraryStore.addAttachments(from: urls) else { return }
                    inferenceStore.generationPreferences.codingAgentPreference =
                        ToolAttachmentSupport.preferenceAfterAddingAttachments(
                            inferenceStore.generationPreferences.codingAgentPreference
                        )
                },
                onRemoveAttachment: { id in
                    toolLibraryStore.removeAttachment(id: id)
                },
                onSelectCustomCodingAgent: { id in
                    inferenceStore.customCodingAgents.selectedAgentID = id
                    inferenceStore.generationPreferences.codingAgentPreference = .custom
                },
                onAddCustomCodingAgent: {
                    customCodingAgentSheet = .add
                },
                onManageCustomCodingAgents: {
                    customCodingAgentSheet = .manage
                }
            )
            .frame(maxHeight: isPromptExpanded ? .infinity : nil)
        }
    }

    @ViewBuilder
    private var toolCollectionContent: some View {
        if shouldShowEmptyState {
            ToolLibraryEmptyStateView(
                showsNoModelActions: shouldShowNoModelsEmptyState
            )
        } else if visibleTools.isEmpty {
            ContentUnavailableView {
                Label("No Apps Found", systemImage: "magnifyingglass")
            } description: {
                Text("Try searching for a different app name.")
            }
            .frame(maxWidth: .infinity, minHeight: 180)
            .accessibilityIdentifier("tool-search-empty-state")
        } else {
            switch viewMode {
            case .list:
                LazyVStack(spacing: 10) {
                    ForEach(visibleTools) { tool in
                        ToolRowView(
                            tool: tool,
                            state: itemState(for: tool),
                            actions: itemActions(for: tool)
                        )
                    }
                }
            case .icons:
                LazyVGrid(columns: iconGridColumns, spacing: 14) {
                    ForEach(visibleTools) { tool in
                        ToolGridItemView(
                            tool: tool,
                            state: itemState(for: tool),
                            actions: itemActions(for: tool)
                        )
                    }
                }
            }
        }
    }

    private var iconGridColumns: [GridItem] {
        Array(repeating: GridItem(.flexible(), spacing: 8), count: 4)
    }

    private func collapsePromptIfNeeded() {
        guard isPromptExpanded else { return }
        withAnimation(.easeInOut(duration: 0.24)) {
            isPromptExpanded = false
        }
    }

    private var viewMode: ToolLibraryViewMode {
        ToolLibraryViewMode.resolved(viewModeRawValue)
    }

    private var sortOrder: ToolLibrarySortOrder {
        ToolLibrarySortOrder.resolved(sortOrderRawValue)
    }

    private var visibleTools: [Tool] {
        ToolLibraryPresentation.visibleTools(
            from: tools,
            searchText: searchText,
            sortOrder: sortOrder
        )
    }

    private var viewModeBinding: Binding<ToolLibraryViewMode> {
        Binding(
            get: { viewMode },
            set: { viewModeRawValue = $0.rawValue }
        )
    }

    private var sortOrderBinding: Binding<ToolLibrarySortOrder> {
        Binding(
            get: { sortOrder },
            set: { sortOrderRawValue = $0.rawValue }
        )
    }

    private func itemState(for tool: Tool) -> ToolItemPresentationState {
        ToolItemPresentationState(
            isSelected: toolLibraryStore.isSelected(tool),
            isRunning: toolLibraryStore.isRunning(tool),
            isLaunching: toolLibraryStore.launchingToolID == tool.id,
            isExporting: toolLibraryStore.exportingToolID == tool.id,
            isRebuilding: toolLibraryStore.rebuildingToolID == tool.id,
            isRestoring: toolLibraryStore.restoringToolID == tool.id,
            isEditingDetails: detailsEditor.isWorking && detailsEditor.editingToolID == tool.id,
            isPreparingGeneration: false,
            canRevert: toolLibraryStore.canRestorePreviousVersion(tool),
            isProjectMode: toolLibraryStore.projectMode(for: tool) == .project,
            activeCodingAgent: toolLibraryStore.activeCodingAgent(for: tool),
            canShowAgentOutput: toolLibraryStore.canShowAgentOutput(for: tool),
            permissionAdvisory: toolLibraryStore.permissionAdvisorySummary(for: tool),
            generationWarning: toolLibraryStore.generationWarning(for: tool)
        )
    }

    private func itemActions(for tool: Tool) -> ToolItemActions {
        ToolItemActions(
            onSelect: {
                toolLibraryStore.toggleSelection(
                    for: tool,
                    defaultSettings: defaultGenerationSettings
                )
            },
            onEdit: {
                selectToolForEditing(tool)
            },
            onRun: {
                Task {
                    await toolLibraryStore.run(tool)
                }
            },
            onQuit: {
                Task {
                    await toolLibraryStore.quit(tool)
                }
            },
            onEditDetails: {
                detailsEditor.beginEditing(tool)
            },
            onRebuild: {
                Task {
                    await toolLibraryStore.rebuild(tool, in: modelContext)
                }
            },
            onRevert: {
                Task {
                    await toolLibraryStore.restorePreviousVersion(tool, in: modelContext)
                }
            },
            onShowVersions: {
                versionHistoryTool = tool
            },
            onConvertToProject: {
                toolLibraryStore.convertToProjectMode(tool)
            },
            onExport: {
                Task {
                    await toolLibraryStore.export(tool)
                }
            },
            onShowInFinder: {
                Task {
                    await toolLibraryStore.showInFinder(tool)
                }
            },
            onViewSource: {
                Task {
                    await toolLibraryStore.viewSource(tool)
                }
            },
            onShowAgentOutput: {
                routeStore.open(.agentOutput(tool.id))
            },
            onContinue: {
                toolLibraryStore.continueGeneration(
                    tool,
                    modelContext: modelContext,
                    inferenceStore: inferenceStore
                )
            },
            onDiscard: {
                toolLibraryStore.discardGeneration(tool, in: modelContext)
            },
            onStop: {
                toolLibraryStore.cancelGeneration()
            },
            onDelete: {
                toolPendingDeletion = tool
            }
        )
    }

    @ViewBuilder
    private var detailsEditorSheet: some View {
        @Bindable var detailsEditor = detailsEditor

        if let tool = tools.first(where: { $0.id == detailsEditor.editingToolID }) {
            ToolAppDetailsEditorSheetView(
                previewData: detailsEditor.previewData,
                name: $detailsEditor.name,
                prompt: $detailsEditor.prompt,
                imageProvider: inferenceStore.effectiveImageGenerationProvider,
                canSave: detailsEditor.canSave(tool),
                isGenerating: detailsEditor.isGenerating,
                isSaving: detailsEditor.isSaving,
                errorMessage: detailsEditor.errorMessage,
                onChooseImage: { url in
                    detailsEditor.importIcon(from: url)
                },
                onGenerate: {
                    let provider = inferenceStore.effectiveImageGenerationProvider
                    Task {
                        await detailsEditor.generate(for: tool, provider: provider)
                    }
                },
                onOpenSettings: {
                    routeStore.open(.settings(.root))
                },
                onCancel: {
                    detailsEditor.cancel()
                },
                onSave: {
                    Task {
                        _ = await detailsEditor.save(
                            tool,
                            in: modelContext,
                            rename: { renameTool(tool, to: $0) }
                        )
                    }
                }
            )
        }
    }

    private func handlePopoverAppear() {
        toolLibraryStore.setPopoverVisible(menuBarPopoverPresentationStore.isShown)
        toolLibraryStore.initializeNextGenerationSettingsIfNeeded(defaultGenerationSettings)
        presentWelcomeOnboardingIfNeeded()
        applyPendingToolLibraryRoute()
    }

    private func handlePopoverShow() {
        toolLibraryStore.setPopoverVisible(true)
        if shouldAlwaysShowWelcomeOnboarding {
            hasCheckedWelcomeOnboarding = false
        }
        presentWelcomeOnboardingIfNeeded()
        applyPendingToolLibraryRoute()
    }

    private func handlePopoverClose() {
        toolLibraryStore.setPopoverVisible(false)
        pauseWelcomeOnboardingPresentation()
    }

    private var restoreAvailabilityRefreshID: [String] {
        tools.map { "\($0.id.uuidString)-\($0.updatedAt.timeIntervalSinceReferenceDate)" }
    }

    private var runningApplicationsRefreshID: String {
        let toolIDs = tools.map(\.id.uuidString).sorted().joined(separator: "|")
        return "\(menuBarPopoverPresentationStore.showCount)|\(toolIDs)"
    }

    private var canSubmitPrompt: Bool {
        toolLibraryStore.canSubmitPrompt && inferenceStore.selectedModel != nil
            && !shouldForceNoModels
            && (toolLibraryStore.attachments.isEmpty || selectedModelSupportsAttachments)
    }

    private var attachmentResolutionContext: ToolCodingAgentResolutionContext {
        toolLibraryStore.currentCodingAgentResolutionContext(in: modelContext)
    }

    private var selectedModelSupportsAttachments: Bool {
        inferenceStore.selectedModelSupportsAttachments(
            resolutionContext: attachmentResolutionContext
        )
    }

    private var selectedModelCanUseCodexAttachments: Bool {
        inferenceStore.selectedModelCanUseCodexAttachments()
    }

    private var composerModelPickerTitle: String {
        if shouldForceNoModels {
            return "No model"
        }

        guard inferenceStore.hasLoadedModels else {
            return "Loading model..."
        }

        if let selectedModelDisplayName {
            return selectedModelDisplayName
        }

        if inferenceStore.availableModels.isEmpty {
            return "No model"
        }

        return "Choose model"
    }

    private var isComposerModelPickerEnabled: Bool {
        inferenceStore.hasLoadedModels && !shouldForceNoModels
    }

    private var selectedModelDisplayName: String? {
        guard let selectedModel = inferenceStore.selectedModel else {
            return nil
        }

        return SettingsModelPresentation.displayName(
            for: selectedModel,
            provider: selectedProvider
        )
    }

    private var selectedProvider: ProviderConfig? {
        guard let selectedModel = inferenceStore.selectedModel else {
            return nil
        }

        return inferenceStore.provider(for: selectedModel)
    }

    private var defaultGenerationSettings: ToolGenerationSettings {
        ToolLibraryStore.defaultGenerationSettings(from: inferenceStore.generationPreferences)
    }

    private var sandboxEnabledBinding: Binding<Bool> {
        Binding(
            get: { toolLibraryStore.sandboxEnabled },
            set: { newValue in
                toolLibraryStore.sandboxEnabled = newValue
                toolLibraryStore.rememberCurrentGenerationSettingsForNextGeneration()
            }
        )
    }

    private var appKindPreferenceBinding: Binding<ToolAppKindPreference> {
        Binding(
            get: { toolLibraryStore.appKindPreference },
            set: { toolLibraryStore.setAppKindPreference($0) }
        )
    }

    private var projectModeBinding: Binding<ToolProjectMode> {
        Binding(
            get: { toolLibraryStore.projectModePreference },
            set: { toolLibraryStore.projectModePreference = $0 }
        )
    }

    private var sandboxPermissionsBinding: Binding<GeneratedAppSandboxPermissions> {
        Binding(
            get: { toolLibraryStore.sandboxPermissions },
            set: { newValue in
                toolLibraryStore.sandboxPermissions = newValue
                toolLibraryStore.rememberCurrentGenerationSettingsForNextGeneration()
            }
        )
    }

    private var resourcePermissionsBinding: Binding<GeneratedAppResourcePermissions> {
        Binding(
            get: { toolLibraryStore.resourcePermissions },
            set: { newValue in
                toolLibraryStore.resourcePermissions = newValue
                toolLibraryStore.rememberCurrentGenerationSettingsForNextGeneration()
            }
        )
    }

    private var codingAgentPreferenceBinding: Binding<ToolCodingAgentPreference> {
        Binding(
            get: { inferenceStore.generationPreferences.codingAgentPreference },
            set: { newValue in
                inferenceStore.generationPreferences.codingAgentPreference = newValue
            }
        )
    }

    private var reasoningEffortBinding: Binding<ToolReasoningEffort> {
        Binding(
            get: { inferenceStore.generationPreferences.reasoningEffort },
            set: { inferenceStore.generationPreferences.reasoningEffort = $0 }
        )
    }

    private func requestPromptSubmission() {
        guard inferenceStore.selectedModel != nil, !shouldForceNoModels else { return }
        submitCurrentPrompt()
    }

    private func submitCurrentPrompt() {
        collapsePromptIfNeeded()
        if !showSandboxOverride {
            toolLibraryStore.sandboxEnabled = true
        }
        toolLibraryStore.startPromptSubmission(
            modelContext: modelContext,
            inferenceStore: inferenceStore
        )
    }

    private func renameTool(_ tool: Tool, to proposedName: String) -> String? {
        guard toolLibraryStore.rename(tool, to: proposedName, in: modelContext) else {
            let message =
                toolLibraryStore.presentedErrorMessage
                ?? "Anvil could not rename this app."
            toolLibraryStore.clearPresentedError()
            return message
        }
        return nil
    }

    private func selectToolForEditing(_ tool: Tool, focusPrompt: Bool = true) {
        toolLibraryStore.selectForEditing(tool, defaultSettings: defaultGenerationSettings)
        isPromptFocused = focusPrompt
    }

    private func applyPendingToolLibraryRoute() {
        guard let route = routeStore.consumeToolLibraryRoute() else { return }
        switch route {
        case .selectTool(let id, let focusPrompt):
            guard let tool = tools.first(where: { $0.id == id }) else { return }
            toolLibraryStore.selectForEditing(tool, defaultSettings: defaultGenerationSettings)
            isPromptFocused = focusPrompt
        }
    }

    private var shouldShowEmptyState: Bool {
        shouldForceNoApps || tools.isEmpty
    }

    private var shouldShowNoModelsEmptyState: Bool {
        shouldForceNoModels
            || (inferenceStore.hasLoadedModels && inferenceStore.availableModels.isEmpty)
    }

    private var shouldForceNoApps: Bool {
        #if DEBUG
            debugPopoverEmptyStateMode.forcesNoApps
        #else
            false
        #endif
    }

    private var shouldForceNoModels: Bool {
        #if DEBUG
            debugPopoverEmptyStateMode.forcesNoModels
        #else
            false
        #endif
    }

    #if DEBUG
        private var debugPopoverEmptyStateMode: ToolLibraryDebugPopoverEmptyStateMode {
            ToolLibraryDebugPopoverEmptyStateMode(rawValue: debugPopoverEmptyStateModeRawValue)
                ?? .off
        }
    #endif

    private func presentWelcomeOnboardingIfNeeded() {
        guard inferenceStore.hasLoadedModels else { return }
        guard !hasCheckedWelcomeOnboarding else { return }
        guard !isShowingWelcomeOnboarding else { return }

        hasCheckedWelcomeOnboarding = true
        guard shouldAlwaysShowWelcomeOnboarding || !welcomeOnboardingStore.hasCompleted else {
            return
        }

        isShowingWelcomeOnboarding = true
    }

    private var shouldAlwaysShowWelcomeOnboarding: Bool {
        #if DEBUG
            debugAlwaysShowWelcomeOnboarding
        #else
            false
        #endif
    }

    private func completeWelcomeOnboarding() {
        welcomeOnboardingStore.complete()
        isShowingWelcomeOnboarding = false
    }

    private func dismissWelcomeOnboardingPresentation() {
        isShowingWelcomeOnboarding = false
        if !welcomeOnboardingStore.hasCompleted {
            hasCheckedWelcomeOnboarding = false
        }
    }

    private func pauseWelcomeOnboardingPresentation() {
        guard isShowingWelcomeOnboarding else { return }
        dismissWelcomeOnboardingPresentation()
    }

    private var deleteConfirmationBinding: Binding<Bool> {
        Binding(
            get: { toolPendingDeletion != nil },
            set: { isPresented in
                if !isPresented {
                    toolPendingDeletion = nil
                }
            }
        )
    }

    private var toolLibraryErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { toolLibraryStore.presentedErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    toolLibraryStore.clearPresentedError()
                }
            }
        )
    }

    private var modelFallbackPresentedBinding: Binding<Bool> {
        Binding(
            get: { inferenceStore.selectedModelFallbackMessage != nil },
            set: { isPresented in
                if !isPresented {
                    inferenceStore.clearSelectedModelFallbackMessage()
                }
            }
        )
    }

    private var signInErrorPresentedBinding: Binding<Bool> {
        Binding(
            get: { inferenceStore.presentedErrorMessage != nil },
            set: { isPresented in
                if !isPresented {
                    inferenceStore.clearPresentedError()
                }
            }
        )
    }

}
#Preview("Tool Library") {
    let container = try! AnvilModelContainerFactory.make(isRunningTests: true)
    let menuBarPopoverPresentationStore = MenuBarPopoverPresentationStore()
    return ToolLibraryPopoverView()
        .modelContainer(container)
        .environment(InferenceStore())
        .environment(AnvilRouteStore(openSettingsWindow: {}))
        .environment(menuBarPopoverPresentationStore)
}
