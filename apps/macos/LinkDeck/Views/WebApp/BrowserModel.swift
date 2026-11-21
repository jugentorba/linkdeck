import AppKit
import Combine
import Foundation
import WebKit
import os

@MainActor
final class BrowserModel: NSObject, ObservableObject {
    let link: DeckLink
    let webView: WKWebView

    @Published private(set) var blockedSession = 0
    @Published private(set) var canGoBack = false
    @Published private(set) var currentURL: URL?
    @Published private(set) var isLoading = true
    @Published private(set) var progress: Double = 0
    @Published private(set) var desktopMode = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var headerVisible = true

    var onClose: (() -> Void)?

    private let settings: AppSettings
    private let store: DeckStore
    private let blocklist: BlocklistService
    private let onPin: (String, String) -> Void
    private let onRemove: () -> Void
    private let logger = Logger(subsystem: "dev.linkdeck.mac", category: "browser")
    private let cosmeticSource: String?
    private let messageHandlerName = "linkdeckStats"

    private var statsBridge: StatsBridge?
    private var observations: [NSKeyValueObservation] = []
    private var cancellables = Set<AnyCancellable>()
    private var hideTask: Task<Void, Never>?
    private var headerHovered = false
    private var didWarnAboutHost = false

    private static let desktopUserAgent =
        "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Safari/605.1.15"

    var host: String {
        currentURL?.host ?? link.host
    }

    var isSecure: Bool {
        currentURL?.scheme?.lowercased() == "https"
    }

    init(
        link: DeckLink,
        settings: AppSettings,
        store: DeckStore,
        blocklist: BlocklistService,
        onPin: @escaping (String, String) -> Void,
        onRemove: @escaping () -> Void
    ) {
        self.link = link
        self.settings = settings
        self.store = store
        self.blocklist = blocklist
        self.onPin = onPin
        self.onRemove = onRemove
        self.currentURL = URL(string: link.url)

        if let url = Bundle.main.url(forResource: "cosmetic", withExtension: "js") {
            cosmeticSource = try? String(contentsOf: url, encoding: .utf8)
        } else {
            cosmeticSource = nil
        }

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true

        let controller = WKUserContentController()
        configuration.userContentController = controller
        webView = WKWebView(frame: .zero, configuration: configuration)

        super.init()

        if cosmeticSource == nil {
            logger.error("cosmetic.js is missing from the app bundle")
        }

        let bridge = StatsBridge(model: self)
        statsBridge = bridge
        controller.add(bridge, name: messageHandlerName)

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.allowsLinkPreview = true

        observeWebView()
        observeSettings()
        applyUserScripts()
        start()
    }

    // MARK: - Actions

    func reload() {
        if webView.url == nil {
            loadInitial()
        } else {
            webView.reload()
        }
        revealHeader()
    }

    func goBackOrClose() {
        if webView.canGoBack {
            webView.goBack()
        } else {
            onClose?()
        }
        revealHeader()
    }

    func toggleDesktopSite() {
        desktopMode.toggle()
        webView.customUserAgent = desktopMode ? Self.desktopUserAgent : nil
        webView.reload()
        revealHeader()
    }

    func openInSafari() {
        guard let url = webView.url else { return }
        NSWorkspace.shared.open(url)
        revealHeader()
    }

    func pinCurrentSite() {
        let url = webView.url?.absoluteString ?? link.url
        onPin(link.name, url)
        revealHeader()
    }

    func removeFromDeck() {
        onRemove()
    }

    func markBlocked(_ count: Int) {
        guard count > 0 else { return }
        blockedSession += count
        store.addBlocked(count, linkID: link.id, url: link.url)
    }

    // MARK: - Header auto-hide

    func revealHeader() {
        headerVisible = true
        scheduleHeaderHide()
    }

    func headerHoverChanged(_ hovering: Bool) {
        headerHovered = hovering
        if hovering {
            hideTask?.cancel()
        } else {
            scheduleHeaderHide()
        }
    }

    private func scheduleHeaderHide() {
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard let self, !Task.isCancelled, !self.headerHovered else { return }
            self.headerVisible = false
        }
    }

    // MARK: - Loading and filters

    private func start() {
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.settings.blockAds {
                await self.applyRuleList()
            }
            self.loadInitial()
            self.scheduleHeaderHide()
        }
    }

    private func loadInitial() {
        guard let url = LinkInput.normalizedURL(from: link.url) else {
            errorMessage = "This link does not have a valid web address."
            isLoading = false
            return
        }
        isLoading = true
        webView.load(URLRequest(url: url))
    }

    private func applyRuleList() async {
        let controller = webView.configuration.userContentController
        controller.removeAllContentRuleLists()
        guard settings.blockAds else { return }
        if let list = await blocklist.ruleList() {
            controller.add(list)
        }
    }

    private func applyUserScripts() {
        let controller = webView.configuration.userContentController
        controller.removeAllUserScripts()
        guard let cosmeticSource else { return }

        // cosmetic.js honours these flags so blocking and popup guards can be
        // toggled independently without forking the shared script.
        let allowPopups = settings.blockPopups ? "false" : "true"
        let blockAds = settings.blockAds ? "true" : "false"
        let source = "window.__linkdeckAllowPopups = \(allowPopups);\nwindow.__linkdeckBlockAds = \(blockAds);\n" + cosmeticSource
        controller.addUserScript(
            WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: false)
        )
    }

    private func observeSettings() {
        settings.$blockAds
            .combineLatest(settings.$blockPopups)
            .dropFirst()
            .sink { [weak self] _, _ in
                guard let self else { return }
                self.applyUserScripts()
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    await self.applyRuleList()
                    self.webView.reload()
                }
            }
            .store(in: &cancellables)
    }

    private func observeWebView() {
        observations.append(webView.observe(\.canGoBack, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                self.canGoBack = webView.canGoBack
            }
        })
        observations.append(webView.observe(\.estimatedProgress, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                self.progress = webView.estimatedProgress
            }
        })
        observations.append(webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
            DispatchQueue.main.async {
                guard let self, let webView else { return }
                self.currentURL = webView.url
            }
        })
    }

    private func syncFromWebView() {
        canGoBack = webView.canGoBack
        progress = webView.estimatedProgress
        if let url = webView.url {
            currentURL = url
        }
    }

    private func warnIfHostIsBlocked() {
        guard !didWarnAboutHost,
              let host = URL(string: link.url)?.host?.lowercased(),
              blocklist.isBlocked(host: host),
              !settings.hasWarned(host: host),
              let window = webView.window,
              window.attachedSheet == nil else {
            return
        }

        didWarnAboutHost = true
        settings.markWarned(host: host)

        let alert = NSAlert()
        alert.messageText = "\(host) is on the block list"
        alert.informativeText = "You chose to open it anyway, so the page will load. LinkDeck still blocks its known ad and tracker hosts."
        alert.addButton(withTitle: "Continue")
        alert.beginSheetModal(for: window)
    }

    private func present(_ alert: NSAlert, completion: @escaping (NSApplication.ModalResponse) -> Void) {
        if let window = webView.window, window.attachedSheet == nil {
            alert.beginSheetModal(for: window, completionHandler: completion)
        } else {
            completion(alert.runModal())
        }
    }
}

// MARK: - Navigation

extension BrowserModel: WKNavigationDelegate {
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        isLoading = true
        errorMessage = nil
        progress = max(progress, 0.04)
        revealHeader()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        syncFromWebView()
        warnIfHostIsBlocked()
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        progress = 1
        syncFromWebView()
        scheduleHeaderHide()
        warnIfHostIsBlocked()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        webView.reload()
    }

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        let allowedSchemes: Set<String> = ["http", "https", "about", "data", "blob", "file"]
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           !allowedSchemes.contains(scheme) {
            NSWorkspace.shared.open(url)
            decisionHandler(.cancel)
            return
        }
        // Top-level navigation is always allowed; the rule list only filters
        // subresources, so a site chosen by the user is never blocked.
        decisionHandler(.allow)
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        isLoading = false
        syncFromWebView()
        errorMessage = nsError.localizedDescription
        revealHeader()
    }
}

// MARK: - Window and dialogs

extension BrowserModel: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if let url = navigationAction.request.url {
            webView.load(URLRequest(url: url))
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        present(alert) { _ in completionHandler() }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = message
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            completionHandler(response == .alertFirstButtonReturn)
        }
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        let alert = NSAlert()
        alert.messageText = prompt
        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 260, height: 24))
        field.stringValue = defaultText ?? ""
        alert.accessoryView = field
        alert.addButton(withTitle: "OK")
        alert.addButton(withTitle: "Cancel")
        present(alert) { response in
            completionHandler(response == .alertFirstButtonReturn ? field.stringValue : nil)
        }
    }
}

// MARK: - Stats bridge

private final class StatsBridge: NSObject, WKScriptMessageHandler {
    weak var model: BrowserModel?

    init(model: BrowserModel) {
        self.model = model
    }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "linkdeckStats", let number = message.body as? NSNumber else { return }
        let value = max(0, min(number.intValue, 500))
        guard value > 0 else { return }
        Task { @MainActor [weak model] in
            model?.markBlocked(value)
        }
    }
}
