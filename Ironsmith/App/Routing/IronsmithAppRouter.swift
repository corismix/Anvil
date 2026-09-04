import AppKit
import Foundation
import Observation

enum IronsmithAppURL {
    /// Custom URL scheme used for deep links and OAuth callbacks.
    static let callbackScheme = "com.jeidoban.ironsmith"
}

enum IronsmithAppRoute: Equatable {
    case agentOutput(UUID)
    case settings(IronsmithSettingsRoute)
    case toolLibrary(IronsmithToolLibraryRoute)

    init?(url: URL) {
        if let settingsRoute = IronsmithSettingsRoute(url: url) {
            self = .settings(settingsRoute)
            return
        }
        return nil
    }
}

enum IronsmithSettingsRoute: Equatable {
    case root
    case addProvider(initialKind: ProviderKind?)
    case editProvider(identifier: String)
    case modelSelection

    init?(url: URL) {
        guard url.scheme == IronsmithAppURL.callbackScheme else {
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

enum IronsmithToolLibraryRoute: Equatable {
    case selectTool(id: UUID, focusPrompt: Bool)
}

@MainActor
@Observable
final class IronsmithRouteStore {
    private let openAgentOutputWindow: @MainActor @Sendable (UUID) -> Void
    private let openSettingsWindow: @MainActor @Sendable () -> Void
    private let openToolLibraryPopover: @MainActor @Sendable () -> Void
    private(set) var pendingSettingsRoute: IronsmithSettingsRoute?
    private(set) var pendingToolLibraryRoute: IronsmithToolLibraryRoute?

    init(
        openAgentOutputWindow: @escaping @MainActor @Sendable (UUID) -> Void = { _ in },
        openSettingsWindow: @escaping @MainActor @Sendable () -> Void,
        openToolLibraryPopover: @escaping @MainActor @Sendable () -> Void = {}
    ) {
        self.openAgentOutputWindow = openAgentOutputWindow
        self.openSettingsWindow = openSettingsWindow
        self.openToolLibraryPopover = openToolLibraryPopover
    }

    func open(_ route: IronsmithAppRoute) {
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
        guard let route = IronsmithAppRoute(url: url) else {
            return false
        }
        open(route)
        return true
    }

    func consumeSettingsRoute() -> IronsmithSettingsRoute? {
        defer { pendingSettingsRoute = nil }
        return pendingSettingsRoute
    }

    func consumeToolLibraryRoute() -> IronsmithToolLibraryRoute? {
        defer { pendingToolLibraryRoute = nil }
        return pendingToolLibraryRoute
    }
}
