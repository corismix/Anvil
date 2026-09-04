import AppKit
import Foundation
import Observation

enum AnvilAppURL {
    /// Custom URL scheme used for deep links and OAuth callbacks.
    static let callbackScheme = "com.corismix.anvil"
}

enum AnvilAppRoute: Equatable {
    case agentOutput(UUID)
    case settings(AnvilSettingsRoute)
    case toolLibrary(AnvilToolLibraryRoute)

    init?(url: URL) {
        if let settingsRoute = AnvilSettingsRoute(url: url) {
            self = .settings(settingsRoute)
            return
        }
        return nil
    }
}

enum AnvilSettingsRoute: Equatable {
    case root
    case addProvider(initialKind: ProviderKind?)
    case editProvider(identifier: String)
    case modelSelection

    init?(url: URL) {
        guard url.scheme == AnvilAppURL.callbackScheme else {
            return nil
        }

        let host = url.host()
        let path = url.pathComponents.filter { $0 != "/" }

        if host == "auth", path == ["callback"] {
            return nil
        }

        guard host == "settings" else {
            return nil
        }

        switch path {
        case []:
            self = .root
        case ["add-provider"]:
            self = .addProvider(initialKind: Self.providerKindQueryValue(from: url))
        case ["model-selection"]:
            self = .modelSelection
        default:
            if path.count == 2, path[0] == "provider" {
                self = .editProvider(identifier: path[1])
                return
            }
            return nil
        }
    }

    private static func providerKindQueryValue(from url: URL) -> ProviderKind? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?
            .first { $0.name == "kind" }?
            .value
            .flatMap(ProviderKind.init(rawValue:))
    }
}

enum AnvilToolLibraryRoute: Equatable {
    case selectTool(id: UUID, focusPrompt: Bool)
}

@MainActor
@Observable
final class AnvilRouteStore {
    private let openAgentOutputWindow: @MainActor @Sendable (UUID) -> Void
    private let openSettingsWindow: @MainActor @Sendable () -> Void
    private let openToolLibraryPopover: @MainActor @Sendable () -> Void
    private(set) var pendingSettingsRoute: AnvilSettingsRoute?
    private(set) var pendingToolLibraryRoute: AnvilToolLibraryRoute?

    init(
        openAgentOutputWindow: @escaping @MainActor @Sendable (UUID) -> Void = { _ in },
        openSettingsWindow: @escaping @MainActor @Sendable () -> Void,
        openToolLibraryPopover: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.openAgentOutputWindow = openAgentOutputWindow
        self.openSettingsWindow = openSettingsWindow
        self.openToolLibraryPopover = openToolLibraryPopover
    }

    func open(_ route: AnvilAppRoute) {
        switch route {
        case .agentOutput(let toolID):
            openAgentOutputWindow(toolID)
        case .settings(let settingsRoute):
            pendingSettingsRoute = settingsRoute
            openSettingsWindow()
        case .toolLibrary(let toolLibraryRoute):
            pendingToolLibraryRoute = toolLibraryRoute
            openToolLibraryPopover()
        }
    }

    @discardableResult
    func handle(_ url: URL) -> Bool {
        guard let route = AnvilAppRoute(url: url) else {
            return false
        }
        open(route)
        return true
    }

    func consumeSettingsRoute() -> AnvilSettingsRoute? {
        defer { pendingSettingsRoute = nil }
        return pendingSettingsRoute
    }

    func consumeToolLibraryRoute() -> AnvilToolLibraryRoute? {
        defer { pendingToolLibraryRoute = nil }
        return pendingToolLibraryRoute
    }
}
