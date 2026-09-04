import AppKit
import SwiftUI
import Testing
@testable import Anvil

struct MenuBarControllerTests {
    @MainActor
    @Test
    func appActivationChangesWindowLevelWithoutClosingShownPopover() throws {
        let popover = TestPopover(isShown: true)
        let presentationStore = MenuBarPopoverPresentationStore()
        presentationStore.didShow()
        let controller = AnvilMenuBarController(
            rootView: AnyView(EmptyView()),
            presentationStore: presentationStore,
            popover: popover
        )
        let contentViewController = try #require(popover.contentViewController)
        let popoverWindow = NSWindow(contentViewController: contentViewController)

        controller.updatePopoverWindowLevel(
            activatedApplicationBundleIdentifier: "com.apple.TextEdit",
            isCurrentApplication: false
        )

        #expect(popoverWindow.level == .floating)
        #expect(popover.closeCount == 0)
        #expect(presentationStore.isShown)

        controller.updatePopoverWindowLevel(
            activatedApplicationBundleIdentifier: ToolBundleIdentifier.make(
                executableName: "Generated Tool"
            ),
            isCurrentApplication: false
        )

        #expect(popoverWindow.level == .normal)
        #expect(popover.closeCount == 0)

        controller.updatePopoverWindowLevel(
            activatedApplicationBundleIdentifier: Bundle.main.bundleIdentifier,
            isCurrentApplication: true
        )

        #expect(popoverWindow.level == .normal)
        #expect(popover.closeCount == 0)
        #expect(presentationStore.closeCount == 0)
    }

    @Test
    func windowLevelPolicyTreatsUnknownBundleIdentifiersAsExternal() {
        #expect(
            AnvilMenuBarController.popoverWindowLevel(
                activatedApplicationBundleIdentifier: nil,
                isCurrentApplication: false
            ) == .floating
        )
    }

    @MainActor
    @Test
    func showingPopoverOrdersItBehindExistingAnvilWindows() {
        let popover = TestPopover(isShown: true)
        let controller = AnvilMenuBarController(
            rootView: AnyView(EmptyView()),
            presentationStore: nil,
            popover: popover
        )
        let popoverWindow = TestWindow(isVisible: true)
        let frontAnvilWindow = TestWindow(isVisible: true)
        let backAnvilWindow = TestWindow(isVisible: true)
        let hiddenWindow = TestWindow(isVisible: false)
        var orderedPopover: NSWindow?
        var orderedBehindWindow: NSWindow?

        controller.orderPopoverBehindAnvilWindows(
            popoverWindow,
            orderedWindows: [
                frontAnvilWindow,
                popoverWindow,
                backAnvilWindow,
                hiddenWindow,
            ]
        ) { popoverWindow, otherWindow in
            orderedPopover = popoverWindow
            orderedBehindWindow = otherWindow
        }

        #expect(orderedPopover === popoverWindow)
        #expect(orderedBehindWindow === backAnvilWindow)
    }
}

private final class TestPopover: NSPopover {
    private var reportsShown: Bool
    private(set) var closeCount = 0

    init(isShown: Bool) {
        reportsShown = isShown
        super.init()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isShown: Bool {
        reportsShown
    }

    override func performClose(_ sender: Any?) {
        closeCount += 1
        reportsShown = false
    }
}

private final class TestWindow: NSWindow {
    private let reportsVisible: Bool

    init(isVisible: Bool) {
        reportsVisible = isVisible
        super.init(
            contentRect: .zero,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isVisible: Bool {
        reportsVisible
    }
}
