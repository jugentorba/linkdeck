import AppKit
import SwiftUI

@MainActor
final class BrowserWindowController: NSObject, NSWindowDelegate {
    let link: DeckLink
    let window: NSWindow
    let model: BrowserModel
    let ui = BrowserUIModel()

    var onClosed: (() -> Void)?

    init(
        link: DeckLink,
        settings: AppSettings,
        store: DeckStore,
        blocklist: BlocklistService,
        onPin: @escaping (String, String) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.link = link

        window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1100, height: 760),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
            backing: .buffered,
            defer: false
        )
        window.title = link.name
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.titlebarSeparatorStyle = .none
        window.backgroundColor = .black
        window.minSize = NSSize(width: 420, height: 300)
        window.isReleasedWhenClosed = false
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.tabbingMode = .disallowed
        window.center()

        model = BrowserModel(
            link: link,
            settings: settings,
            store: store,
            blocklist: blocklist,
            onPin: onPin,
            onRemove: onRemove
        )

        super.init()

        model.onClose = { [weak self] in
            self?.window.performClose(nil)
        }

        let view = WebAppView(
            model: model,
            settings: settings,
            store: store,
            ui: ui,
            blocklist: blocklist
        )
        let hosting = NSHostingView(rootView: view)
        window.contentView = hosting
        window.delegate = self
    }

    func showWindow() {
        window.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        onClosed?()
    }
}
