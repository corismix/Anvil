import Foundation
import FoundationModels
import SwiftData

enum AppDataBootstrapper {
    static func bootstrapIfNeeded(in context: ModelContext) throws {
        try IronsmithPaths.ensureDirectoriesExist()

        let providers = try context.fetch(FetchDescriptor<ProviderConfig>())

        // Pre-fork databases may still hold the removed backend provider and its
        // remote models. Delete them so nothing references the dead service.
        let removedBackendProviderIdentifiers = [ProviderKind.ironsmith.rawValue]
        for provider in providers where removedBackendProviderIdentifiers.contains(provider.identifier) {
            context.delete(provider)
        }
        let allModels = try context.fetch(FetchDescriptor<ModelConfig>())
        for model in allModels where removedBackendProviderIdentifiers.contains(model.providerIdentifier) {
            context.delete(model)
        }

        if !providers.contains(where: { $0.identifier == ProviderConfig.localProviderIdentifier }) {
            let provider = ProviderCatalog.makeProvider(for: .local) ?? ProviderConfig(
                identifier: ProviderConfig.localProviderIdentifier,
                displayName: "Local",
                baseURLString: "",
                authMode: .none,
                origin: .builtIn
            )
            context.insert(provider)
        }

        let existingModels = allModels.filter { $0.providerIdentifier != ProviderKind.ironsmith.rawValue }
        if !existingModels.contains(where: {
            $0.identifier == ModelConfig.appleFoundationIdentifier &&
            $0.providerIdentifier == ProviderConfig.localProviderIdentifier
        }) {
            if IronsmithRuntimeEnvironment.isRunningTests || SystemLanguageModel.default.availability == .available {
                let model = ModelConfig(
                    identifier: ModelConfig.appleFoundationIdentifier,
                    displayName: "Apple Foundation Model",
                    providerIdentifier: ProviderConfig.localProviderIdentifier,
                    source: .appleFoundation,
                    installState: .builtIn
                )
                context.insert(model)
            }
        }

        if context.hasChanges {
            try context.save()
        }
    }
}
