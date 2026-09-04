import AppKit
import SwiftData
import SwiftUI

@MainActor
final class AnvilAppDelegate: NSObject, NSApplicationDelegate {
    private var applicationController: AnvilApplicationController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AnvilEditCommandMenu.installIfNeeded()
        let applicationController = AnvilApplicationController()
        self.applicationController = applicationController
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(200)) {
            applicationController.showToolLibraryPopover()
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        applicationController?.handle(urls)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }
}

@MainActor
private enum AnvilEditCommandMenu {
    static func installIfNeeded() {
        let mainMenu = NSApp.mainMenu ?? NSMenu(title: "Anvil")
        if NSApp.mainMenu == nil {
            NSApp.mainMenu = mainMenu
        }

        if mainMenu.items.isEmpty {
            let appMenuItem = NSMenuItem()
            let appMenu = NSMenu(title: "Anvil")
            appMenu.addItem(withTitle: "Quit Anvil", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            appMenuItem.submenu = appMenu
            mainMenu.addItem(appMenuItem)
        }

        guard !mainMenu.items.contains(where: { $0.submenu?.title == "Edit" }) else { return }

        let editMenuItem = NSMenuItem()
        let editMenu = NSMenu(title: "Edit")
        editMenuItem.submenu = editMenu

        editMenu.addItem(makeMenuItem(title: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        editMenu.addItem(makeMenuItem(title: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        editMenu.addItem(makeMenuItem(title: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        editMenu.addItem(NSMenuItem.separator())
        editMenu.addItem(makeMenuItem(title: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))

        mainMenu.addItem(editMenuItem)
    }

    private static func makeMenuItem(
        title: String,
        action: Selector,
        keyEquivalent: String
    ) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: keyEquivalent)
        item.keyEquivalentModifierMask = [.command]
        item.target = nil
        return item
    }
}

@MainActor
final class AnvilApplicationController {
    private let modelContainer: ModelContainer
    private let inferenceStore: InferenceStore
    private let routeStore: AnvilRouteStore
    private let commandLineToolsGate: CommandLineToolsGate
    private let menuBarPopoverPresentationStore: MenuBarPopoverPresentationStore
    private let menuBarController: AnvilMenuBarController?
    private let agentOutputWindowController: AnvilAgentOutputWindowController?
    private let settingsWindowController: AnvilSettingsWindowController?

    init(codexPluginInstaller: CodexPluginInstaller = .live()) {
        let isRunningTests = AnvilRuntimeEnvironment.isRunningTests
        let inferenceStore = InferenceStore()
        var appKitAgentOutputWindowController: AnvilAgentOutputWindowController?
        var appKitSettingsWindowController: AnvilSettingsWindowController?
        var appKitMenuBarController: AnvilMenuBarController?
        let routeStore = AnvilRouteStore(
            openAgentOutputWindow: { toolID in
                appKitAgentOutputWindowController?.show(toolID: toolID)
            },
            openSettingsWindow: {
                appKitSettingsWindowController?.show()
            },
            openToolLibraryPopover: {
                appKitMenuBarController?.show()
            }
        )
        let commandLineToolsGate = CommandLineToolsGate()
        let menuBarPopoverPresentationStore = MenuBarPopoverPresentationStore()

        do {
            modelContainer = try AnvilModelContainerFactory.make(isRunningTests: isRunningTests)
            let context = ModelContext(modelContainer)
            try AppDataBootstrapper.bootstrapIfNeeded(in: context)
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }

        self.inferenceStore = inferenceStore
        self.routeStore = routeStore
        self.commandLineToolsGate = commandLineToolsGate
        self.menuBarPopoverPresentationStore = menuBarPopoverPresentationStore
        if isRunningTests {
            agentOutputWindowController = nil
            settingsWindowController = nil
            menuBarController = nil
        } else {
            let agentOutputWindowController = AnvilAgentOutputWindowController(
                modelContainer: modelContainer
            )
            appKitAgentOutputWindowController = agentOutputWindowController
            self.agentOutputWindowController = agentOutputWindowController
            let settingsWindowController = AnvilSettingsWindowController(
                modelContainer: modelContainer,
                inferenceStore: inferenceStore,
                routeStore: routeStore
            )
            appKitSettingsWindowController = settingsWindowController
            self.settingsWindowController = settingsWindowController
            let menuBarController = AnvilMenuBarController(
                rootView: AnyView(
                    LaunchRouterView(gate: commandLineToolsGate)
                        .modelContainer(modelContainer)
                        .environment(inferenceStore)
                        .environment(routeStore)
                        .environment(menuBarPopoverPresentationStore)
                ),
                presentationStore: menuBarPopoverPresentationStore
            )
            appKitMenuBarController = menuBarController
            self.menuBarController = menuBarController
        }

        Task {
            await codexPluginInstaller.install()
        }
    }

    func handle(_ urls: [URL]) {
        for url in urls {
            routeStore.handle(url)
        }
    }

    func showToolLibraryPopover() {
        menuBarController?.show()
    }
}
