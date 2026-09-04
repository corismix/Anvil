import SwiftData
import SwiftUI

struct SettingsWindowView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(InferenceStore.self) private var inferenceStore
    @Environment(IronsmithRouteStore.self) private var routeStore
    @AppStorage(IronsmithPreferenceKeys.hasPresentedOllamaModelDownloadNudge)
    private var hasPresentedOllamaModelDownloadNudge = false
    #if DEBUG
    @AppStorage(IronsmithPreferenceKeys.debugAlwaysOpenOllamaEditorAfterAdd)
    private var debugAlwaysOpenOllamaEditorAfterAdd = false
    #endif
    @State private var presentedSheet: SettingsPresentedSheet?
    @State private var pendingProviderEditorIdentifierAfterSheetDismissal: String?
    @State private var isShowingNestedSettingsSheet = false
    @State private var hasPreparedSettings = false

    var body: some View {
        Form {
            SettingsProvidersSectionView(
                onAddProvider: { presentedSheet = .addProvider(initialKind: nil) },
                onEditProvider: { presentedSheet = .editProvider($0) }
            )
            SettingsPreferencesSectionView()
            #if DEBUG
            SettingsDebugSectionView()
            #endif
        }
        .formStyle(.grouped)
        .padding(20)
        .frame(minWidth: 680, minHeight: 720)
        .task {
            await inferenceStore.prepareSettings(modelContext: modelContext)
            hasPreparedSettings = true
            consumePendingSettingsRoute()
        }
        .onChange(of: routeStore.pendingSettingsRoute) {
            guard hasPreparedSettings else { return }
            consumePendingSettingsRoute()
        }
        .sheet(
            item: $presentedSheet,
            onDismiss: {
                isShowingNestedSettingsSheet = false
                presentPendingProviderEditorIfNeeded()
            }
        ) { sheet in
            settingsSheetContent(sheet)
                .alert(
                    "Settings Error",
                    isPresented: activeSheetErrorAlertBinding
                ) {
                    Button("OK", role: .cancel) {}
                } message: {
                    Text(inferenceStore.presentedErrorMessage ?? "")
                }
        }
        .alert(
            "Settings Error",
            isPresented: errorAlertBinding
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(inferenceStore.presentedErrorMessage ?? "")
        }
    }

    private func consumePendingSettingsRoute() {
        guard let route = routeStore.consumeSettingsRoute() else {
            return
        }
        apply(route)
    }

    private func apply(_ route: IronsmithSettingsRoute) {
        switch route {
        case .root, .modelSelection:
            presentedSheet = nil
        case .addProvider(let initialKind):
            presentedSheet = .addProvider(initialKind: initialKind)
        case .editProvider(let identifier):
            presentedSheet = inferenceStore.providers
                .first { $0.identifier == identifier }
                .map { SettingsPresentedSheet.editProvider($0) }
        }
    }

    private func handleProviderAdded(_ providerKind: ProviderKind) {
        guard providerKind == .ollama else { return }
        #if DEBUG
        if debugAlwaysOpenOllamaEditorAfterAdd {
            pendingProviderEditorIdentifierAfterSheetDismissal = ProviderKind.ollama.rawValue
            return
        }
        #endif
        guard !hasPresentedOllamaModelDownloadNudge else { return }
        hasPresentedOllamaModelDownloadNudge = true
        pendingProviderEditorIdentifierAfterSheetDismissal = ProviderKind.ollama.rawValue
    }

    private func presentPendingProviderEditorIfNeeded() {
        guard let identifier = pendingProviderEditorIdentifierAfterSheetDismissal else {
            return
        }
        pendingProviderEditorIdentifierAfterSheetDismissal = nil

        presentedSheet = inferenceStore.providers
            .first { $0.identifier == identifier }
            .map { SettingsPresentedSheet.editProvider($0) }
    }

    private var errorAlertBinding: Binding<Bool> {
        Binding(
            get: { inferenceStore.presentedErrorMessage != nil && presentedSheet == nil },
            set: { isPresented in
                if !isPresented {
                    inferenceStore.clearPresentedError()
                }
            }
        )
    }

    private var activeSheetErrorAlertBinding: Binding<Bool> {
        Binding(
            get: {
                inferenceStore.presentedErrorMessage != nil
                    && presentedSheet != nil
                    && !isShowingNestedSettingsSheet
            },
            set: { isPresented in
                if !isPresented {
                    inferenceStore.clearPresentedError()
                }
            }
        )
    }

    @ViewBuilder
    private func settingsSheetContent(_ sheet: SettingsPresentedSheet) -> some View {
        switch sheet {
        case .addProvider(let initialKind):
            AddProviderSheetView(
                initialKind: initialKind,
                onProviderAdded: handleProviderAdded
            )
        case .editProvider(let provider):
            ProviderEditorSheetView(
                provider: provider,
                onNestedSheetPresentationChange: { isPresented in
                    isShowingNestedSettingsSheet = isPresented
                }
            )
        }
    }
}

private enum SettingsPresentedSheet: Identifiable {
    case addProvider(initialKind: ProviderKind?)
    case editProvider(ProviderConfig)

    var id: String {
        switch self {
        case .addProvider(let initialKind):
            "addProvider.\(initialKind?.rawValue ?? "default")"
        case .editProvider(let provider):
            "editProvider.\(provider.id.uuidString)"
        }
    }
}

#Preview("Settings") {
    let container = try! IronsmithModelContainerFactory.make(isRunningTests: true)
    return SettingsWindowView()
        .modelContainer(container)
        .environment(InferenceStore())
        .environment(IronsmithRouteStore(openSettingsWindow: {}))
        .frame(width: 680, height: 720)
}
