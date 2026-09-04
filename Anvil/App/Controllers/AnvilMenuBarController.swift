import AppKit
import SwiftUI

@MainActor
final class AnvilMenuBarController: NSObject, NSPopoverDelegate {
    private let statusItem: NSStatusItem
    private let popover: NSPopover
    private let hostingController: NSHostingController<AnyView>
    private let presentationStore: MenuBarPopoverPresentationStore?

    convenience init(
        rootView: AnyView,
        presentationStore: MenuBarPopoverPresentationStore? = nil
    ) {
        self.init(
            rootView: rootView,
            presentationStore: presentationStore,
            popover: NSPopover()
        )
    }

    init(
        rootView: AnyView,
        presentationStore: MenuBarPopoverPresentationStore?,
        popover: NSPopover
    ) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        self.popover = popover
        hostingController = NSHostingController(rootView: rootView)
        self.presentationStore = presentationStore

        super.init()

        configurePopover()
        configureStatusItem()
        configureWorkspaceApplicationObservation()
    }

    private func configurePopover() {
        if #available(macOS 13.0, *) {
            hostingController.sizingOptions = [.preferredContentSize]
        }

        popover.behavior = .applicationDefined
        popover.animates = true
        popover.contentViewController = hostingController
        popover.delegate = self
    }

    private func configureStatusItem() {
        guard let button = statusItem.button else { return }

        let image = NSImage(named: "AnvilMenubarIcon")
        image?.isTemplate = true
        image?.size = NSSize(width: 26, height: 26)
        image?.accessibilityDescription = "Anvil"

        button.image = image
        button.target = self
        button.action = #selector(togglePopover(_:))
        button.toolTip = "Anvil"
    }

    @objc private func togglePopover(_ sender: Any?) {
        if popover.isShown {
            closePopover(sender)
        } else {
            showPopover()
        }
    }

    func show() {
        showPopover()
    }

    static func popoverWindowLevel(
        activatedApplicationBundleIdentifier: String?,
        isCurrentApplication: Bool
    ) -> NSWindow.Level {
        if isCurrentApplication || ToolBundleIdentifier.isGeneratedApp(activatedApplicationBundleIdentifier) {
            return .normal
        }
        return .floating
    }

    func updatePopoverWindowLevel(
        activatedApplicationBundleIdentifier: String?,
        isCurrentApplication: Bool
    ) {
        guard let popoverWindow = popover.contentViewController?.view.window else { return }

        popoverWindow.level = Self.popoverWindowLevel(
            activatedApplicationBundleIdentifier: activatedApplicationBundleIdentifier,
            isCurrentApplication: isCurrentApplication
        )
        if isCurrentApplication {
            orderPopoverBehindAnvilWindows(popoverWindow)
        }
    }

    func orderPopoverBehindAnvilWindows(
        _ popoverWindow: NSWindow
    ) {
        orderPopoverBehindAnvilWindows(
            popoverWindow,
            orderedWindows: NSApp.orderedWindows
        ) { popoverWindow, otherWindow in
            popoverWindow.order(.below, relativeTo: otherWindow.windowNumber)
        }
    }

    func orderPopoverBehindAnvilWindows(
        _ popoverWindow: NSWindow,
        orderedWindows: [NSWindow],
        performOrder: @MainActor (NSWindow, NSWindow) -> Void
    ) {
        guard
            let backmostNormalWindow = orderedWindows.last(where: {
                $0 !== popoverWindow
                    && $0.isVisible
                    && !$0.isMiniaturized
                    && $0.level == .normal
            })
        else {
            return
        }

        performOrder(popoverWindow, backmostNormalWindow)
    }

    private func configureWorkspaceApplicationObservation() {
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(workspaceApplicationDidActivate(_:)),
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }

    @objc private func workspaceApplicationDidActivate(_ notification: Notification) {
        guard
            let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                as? NSRunningApplication
        else {
            return
        }

        updatePopoverWindowLevel(
            activatedApplicationBundleIdentifier: application.bundleIdentifier,
            isCurrentApplication: application.processIdentifier == ProcessInfo.processInfo.processIdentifier
        )
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }

        NSApp.activate(ignoringOtherApps: true)
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        if let popoverWindow = popover.contentViewController?.view.window {
            // Keep Anvil and its generated apps above the popover. Workspace
            // activation notifications raise it only while an unrelated app is active.
            popoverWindow.level = Self.popoverWindowLevel(
                activatedApplicationBundleIdentifier: Bundle.main.bundleIdentifier,
                isCurrentApplication: true
            )
            popoverWindow.makeKey()
            orderPopoverBehindAnvilWindows(popoverWindow)
        }
        button.state = .on
        presentationStore?.didShow()
    }

    func popoverDidClose(_ notification: Notification) {
        statusItem.button?.state = .off
    }

    private func closePopover(_ sender: Any?) {
        guard popover.isShown else { return }
        presentationStore?.willClose()
        dismissAttachedSheetIfNeeded()
        popover.performClose(sender)
    }

    private func dismissAttachedSheetIfNeeded() {
        guard
            let window = popover.contentViewController?.view.window,
            let attachedSheet = window.attachedSheet
        else {
            return
        }

        window.endSheet(attachedSheet)
    }

    deinit {
        NSWorkspace.shared.notificationCenter.removeObserver(
            self,
            name: NSWorkspace.didActivateApplicationNotification,
            object: nil
        )
    }
}
