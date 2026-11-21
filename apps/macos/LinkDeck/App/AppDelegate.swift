import AppKit
import Darwin
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuItemValidation {
    let store = DeckStore()
    let settings = AppSettings()
    let blocklist = BlocklistService()

    private(set) var isPinned = false
    private var deckController: DeckWindowController?
    private var browserControllers: [BrowserWindowController] = []

    // MARK: - Lifecycle

    func applicationDidFinishLaunching(_ notification: Notification) {
        if CommandLine.arguments.contains("--self-test") {
            Task { @MainActor in
                let passed = await SelfTest.run(arguments: CommandLine.arguments)
                exit(passed ? 0 : 1)
            }
            return
        }

        NSApp.appearance = NSAppearance(named: .darkAqua)
        NSApp.mainMenu = buildMainMenu()

        if let pinned = PinnedLink.readFromMainBundle() {
            isPinned = true
            let link: DeckLink
            if let existing = store.link(withURL: pinned.url) {
                link = DeckLink(
                    id: existing.id,
                    name: pinned.name,
                    url: pinned.url,
                    addedAt: existing.addedAt,
                    blocked: existing.blocked
                )
            } else {
                link = DeckLink(name: pinned.name, url: pinned.url)
            }
            openApp(link)
        } else {
            showDeck()
        }

        NSApp.activate(ignoringOtherApps: true)

        // Compile the rule list in the background so the first browser window
        // does not have to wait on it.
        Task { [blocklist] in
            _ = await blocklist.ruleList()
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationWillTerminate(_ notification: Notification) {
        store.flush()
    }

    // MARK: - Windows

    func showDeck() {
        if let deckController {
            bringForward(deckController.window)
            return
        }

        let controller = DeckWindowController(
            store: store,
            settings: settings,
            blocklist: blocklist,
            onOpen: { [weak self] link in
                self?.openApp(link)
            },
            onPin: { [weak self] link in
                self?.pinApp(name: link.name, url: link.url)
            },
            onClosed: { [weak self] in
                self?.deckController = nil
            }
        )
        deckController = controller
        controller.showWindow()
    }

    private func openApp(_ link: DeckLink) {
        if let existing = browserControllers.first(where: { $0.link.id == link.id || $0.link.url == link.url }) {
            bringForward(existing.window)
            return
        }

        let controller = BrowserWindowController(
            link: link,
            settings: settings,
            store: store,
            blocklist: blocklist,
            onPin: { [weak self] name, url in
                self?.pinApp(name: name, url: url)
            },
            onRemove: { [weak self] in
                self?.removeFromDeck(link)
            }
        )
        controller.onClosed = { [weak self, weak controller] in
            guard let self, let controller else { return }
            self.browserControllers.removeAll { $0 === controller }
            self.store.flush()
        }
        browserControllers.append(controller)
        controller.showWindow()
        NSApp.activate(ignoringOtherApps: true)
    }

    private func removeFromDeck(_ link: DeckLink) {
        store.remove(id: link.id, url: link.url)
        guard !isPinned,
              let controller = browserControllers.first(where: { $0.link.url == link.url }) else {
            return
        }
        controller.window.performClose(nil)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if let deck = deckController {
            bringForward(deck.window)
        } else if let browser = browserControllers.first {
            bringForward(browser.window)
        } else {
            showDeck()
        }
        return true
    }

    private func bringForward(_ window: NSWindow) {
        if window.isMiniaturized {
            window.deminiaturize(nil)
        }
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private func browserController(for window: NSWindow?) -> BrowserWindowController? {
        guard let window else { return nil }
        return browserControllers.first { $0.window === window }
    }

    private func keyWindow() -> NSWindow? {
        let key = NSApp.keyWindow
        return key?.sheetParent ?? key
    }

    // MARK: - Pin as app

    private func pinApp(name: String, url: String) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let destination = try await PinnedAppBuilder().pin(name: name, url: url)
                self.presentPinSuccess(destination)
            } catch {
                self.presentError(error)
            }
        }
    }

    private func presentPinSuccess(_ destination: URL) {
        let alert = NSAlert()
        alert.messageText = "Pinned to Applications"
        alert.informativeText = "\(destination.deletingPathExtension().lastPathComponent).app is in ~/Applications/LinkDeck. Open it from Finder or Spotlight to launch the site in its own window with its own Dock icon."
        alert.addButton(withTitle: "Reveal in Finder")
        alert.addButton(withTitle: "Done")
        present(alert) { response in
            if response == .alertFirstButtonReturn {
                NSWorkspace.shared.activateFileViewerSelecting([destination])
            }
        }
    }

    private func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Could not pin this app"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "OK")
        present(alert) { _ in }
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = keyWindow(), window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }

    // MARK: - Menu actions

    @objc private func addLink(_ sender: Any?) {
        showDeck()
        DispatchQueue.main.async { [weak self] in
            self?.deckController?.ui.showAddLink = true
        }
    }

    @objc private func showSettings(_ sender: Any?) {
        if let browser = browserController(for: keyWindow()) {
            browser.ui.showSettings = true
            return
        }
        if let deck = deckController {
            deck.window.makeKeyAndOrderFront(nil)
            deck.ui.showSettings = true
            return
        }
        if let browser = browserControllers.first {
            browser.window.makeKeyAndOrderFront(nil)
            browser.ui.showSettings = true
        }
    }

    @objc private func reloadKeyWindow(_ sender: Any?) {
        browserController(for: keyWindow())?.model.reload()
    }

    func validateMenuItem(_ menuItem: NSMenuItem) -> Bool {
        if menuItem.action == #selector(reloadKeyWindow(_:)) {
            return browserController(for: keyWindow()) != nil
        }
        return true
    }

    // MARK: - Main menu

    private func buildMainMenu() -> NSMenu {
        let appName = Bundle.main.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String ?? "LinkDeck"
        let mainMenu = NSMenu()

        let appItem = NSMenuItem()
        mainMenu.addItem(appItem)
        let appMenu = NSMenu(title: appName)
        appItem.submenu = appMenu

        let about = NSMenuItem(
            title: "About \(appName)",
            action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)),
            keyEquivalent: ""
        )
        about.target = NSApp
        appMenu.addItem(about)
        appMenu.addItem(.separator())

        let settingsItem = NSMenuItem(title: "Settings…", action: #selector(showSettings(_:)), keyEquivalent: ",")
        settingsItem.target = self
        appMenu.addItem(settingsItem)
        appMenu.addItem(.separator())

        let hide = NSMenuItem(title: "Hide \(appName)", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
        hide.target = NSApp
        appMenu.addItem(hide)

        let hideOthers = NSMenuItem(
            title: "Hide Others",
            action: #selector(NSApplication.hideOtherApplications(_:)),
            keyEquivalent: "h"
        )
        hideOthers.keyEquivalentModifierMask = [.command, .option]
        hideOthers.target = NSApp
        appMenu.addItem(hideOthers)

        let showAll = NSMenuItem(title: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)), keyEquivalent: "")
        showAll.target = NSApp
        appMenu.addItem(showAll)
        appMenu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit \(appName)", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        quit.target = NSApp
        appMenu.addItem(quit)

        let fileItem = NSMenuItem()
        mainMenu.addItem(fileItem)
        let fileMenu = NSMenu(title: "File")
        fileItem.submenu = fileMenu

        let add = NSMenuItem(title: "Add a Link", action: #selector(addLink(_:)), keyEquivalent: "n")
        add.target = self
        fileMenu.addItem(add)
        fileMenu.addItem(.separator())

        let close = NSMenuItem(title: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        close.target = nil
        fileMenu.addItem(close)

        let editItem = NSMenuItem()
        mainMenu.addItem(editItem)
        let editMenu = NSMenu(title: "Edit")
        editItem.submenu = editMenu
        editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = NSMenuItem(title: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        editMenu.addItem(redo)
        editMenu.addItem(.separator())
        editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

        let viewItem = NSMenuItem()
        mainMenu.addItem(viewItem)
        let viewMenu = NSMenu(title: "View")
        viewItem.submenu = viewMenu
        let reload = NSMenuItem(title: "Reload", action: #selector(reloadKeyWindow(_:)), keyEquivalent: "r")
        reload.target = self
        viewMenu.addItem(reload)

        let windowItem = NSMenuItem()
        mainMenu.addItem(windowItem)
        let windowMenu = NSMenu(title: "Window")
        windowItem.submenu = windowMenu

        let minimize = NSMenuItem(title: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        minimize.target = nil
        windowMenu.addItem(minimize)

        let zoom = NSMenuItem(title: "Zoom", action: #selector(NSWindow.performZoom(_:)), keyEquivalent: "")
        zoom.target = nil
        windowMenu.addItem(zoom)
        windowMenu.addItem(.separator())

        let bringAll = NSMenuItem(title: "Bring All to Front", action: #selector(NSApplication.arrangeInFront(_:)), keyEquivalent: "")
        bringAll.target = NSApp
        windowMenu.addItem(bringAll)
        NSApp.windowsMenu = windowMenu

        return mainMenu
    }
}
