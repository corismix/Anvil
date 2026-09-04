import AppKit
import SwiftUI

@MainActor
final class AnvilAboutWindowController: NSWindowController {
    static let shared = AnvilAboutWindowController()

    private init() {
        let hostingController = NSHostingController(
            rootView: AnvilAboutView()
        )
        let window = NSWindow(contentViewController: hostingController)
        window.title = "About Anvil"
        window.styleMask = [.titled, .closable, .miniaturizable]
        window.isReleasedWhenClosed = false
        window.standardWindowButton(.zoomButton)?.isHidden = true

        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func show() {
        if !(window?.isVisible ?? false) {
            window?.center()
        }

        showWindow(nil)
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
