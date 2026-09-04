import Foundation
import Testing
@testable import Anvil

struct AppRoutingTests {
    @Test
    func appRouteParsesSettingsRootURL() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings"))

        #expect(AnvilAppRoute(url: url) == .settings(.root))
    }

    @Test
    func appRouteParsesAddProviderURL() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings/add-provider"))

        #expect(AnvilAppRoute(url: url) == .settings(.addProvider(initialKind: nil)))
    }

    @Test
    func appRouteParsesAddProviderURLWithInitialKind() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings/add-provider?kind=openai"))

        #expect(AnvilAppRoute(url: url) == .settings(.addProvider(initialKind: .openAI)))
    }

    @Test
    func appRouteKeepsAddProviderURLWhenInitialKindIsInvalid() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings/add-provider?kind=bogus"))

        #expect(AnvilAppRoute(url: url) == .settings(.addProvider(initialKind: nil)))
    }

    @Test
    func appRouteParsesProviderEditorURL() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings/provider/anvil"))

        #expect(AnvilAppRoute(url: url) == .settings(.editProvider(identifier: "anvil")))
    }

    @Test
    func appRouteParsesModelSelectionURL() throws {
        let url = try #require(URL(string: "com.corismix.anvil://settings/model-selection"))

        #expect(AnvilAppRoute(url: url) == .settings(.modelSelection))
    }

    @Test
    func appRouteIgnoresOAuthCallbackURL() throws {
        let url = try #require(URL(string: "com.corismix.anvil://auth/callback?code=test"))

        #expect(AnvilAppRoute(url: url) == nil)
    }

    @Test
    func appRouteRejectsUnsupportedURLs() throws {
        let invalidSchemeURL = try #require(URL(string: "https://settings"))
        let unknownPathURL = try #require(URL(string: "com.corismix.anvil://settings/unknown"))
        let unknownHostURL = try #require(URL(string: "com.corismix.anvil://tools"))

        #expect(AnvilAppRoute(url: invalidSchemeURL) == nil)
        #expect(AnvilAppRoute(url: unknownPathURL) == nil)
        #expect(AnvilAppRoute(url: unknownHostURL) == nil)
    }

    @MainActor
    @Test
    func routeStoreOpensSettingsAndStoresPendingRoute() {
        let capture = SettingsWindowOpenCapture()
        let store = AnvilRouteStore(openSettingsWindow: {
            capture.open()
        })

        store.open(.settings(.addProvider(initialKind: .openAI)))

        #expect(capture.openCount == 1)
        #expect(store.pendingSettingsRoute == .addProvider(initialKind: .openAI))
        #expect(store.consumeSettingsRoute() == .addProvider(initialKind: .openAI))
        #expect(store.pendingSettingsRoute == nil)
    }

    @MainActor
    @Test
    func routeStoreOpensToolLibraryRoutes() throws {
        let settingsCapture = SettingsWindowOpenCapture()
        let popoverCapture = SettingsWindowOpenCapture()
        let toolID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let store = AnvilRouteStore(
            openSettingsWindow: {
                settingsCapture.open()
            },
            openToolLibraryPopover: {
                popoverCapture.open()
            }
        )

        store.open(.toolLibrary(.selectTool(id: toolID, focusPrompt: true)))

        #expect(settingsCapture.openCount == 0)
        #expect(popoverCapture.openCount == 1)
        #expect(store.consumeToolLibraryRoute() == .selectTool(id: toolID, focusPrompt: true))
        #expect(store.pendingToolLibraryRoute == nil)
    }

    @MainActor
    @Test
    func routeStoreOpensPopoverForToolSelection() throws {
        let popoverCapture = SettingsWindowOpenCapture()
        let toolID = try #require(UUID(uuidString: "11111111-2222-4333-8444-555555555555"))
        let store = AnvilRouteStore(
            openSettingsWindow: {},
            openToolLibraryPopover: {
                popoverCapture.open()
            }
        )

        store.open(.toolLibrary(.selectTool(id: toolID, focusPrompt: true)))

        #expect(popoverCapture.openCount == 1)
        #expect(store.consumeToolLibraryRoute() == .selectTool(id: toolID, focusPrompt: true))
    }

    @MainActor
    @Test
    func routeStoreHandlesSupportedURL() throws {
        let capture = SettingsWindowOpenCapture()
        let store = AnvilRouteStore(openSettingsWindow: {
            capture.open()
        })
        let url = try #require(URL(string: "com.corismix.anvil://settings/provider/openai"))

        #expect(store.handle(url))
        #expect(capture.openCount == 1)
        #expect(store.pendingSettingsRoute == .editProvider(identifier: "openai"))
    }

    @MainActor
    @Test
    func routeStoreIgnoresUnsupportedURL() throws {
        let capture = SettingsWindowOpenCapture()
        let store = AnvilRouteStore(openSettingsWindow: {
            capture.open()
        })
        let url = try #require(URL(string: "com.corismix.anvil://auth/callback?code=test"))

        #expect(!store.handle(url))
        #expect(capture.openCount == 0)
        #expect(store.pendingSettingsRoute == nil)
    }
}

@MainActor
private final class SettingsWindowOpenCapture {
    private(set) var openCount = 0

    func open() {
        openCount += 1
    }
}
