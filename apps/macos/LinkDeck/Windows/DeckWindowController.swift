import AppKit
import SwiftUI

@MainActor
final class DeckWindowController: NSObject, NSWindowDelegate {
    let window: NSWindow
    let ui = DeckUIModel()

    private let onClosed: () -> Void

    init(
        store: DeckStore,
        settings: AppSettings,
        blocklist: BlocklistService,
        onOpen: @escaping (DeckLink) -> Void,
        onPin: @escaping (DeckLink) -> Void,
        onClosed: @escaping () -> Void
    ) {
        self.onClosed = onClosed

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 980, height: 720),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = "LinkDeck"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.isMovableByWindowBackground = true
        window.backgroundColor = NSColor(hex: 0x0B0D10)
        window.minSize = NSSize(width: 620, height: 460)
        window.isReleasedWhenClosed = false
        window.center()

        super.init()

        let view = DeckView(
            store: store,
            settings: settings,
            ui: ui,
            blocklist: blocklist,
            onOpen: onOpen,
            onPin: onPin
        )
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.delegate = self
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed()
    }
}
