import Observation
import SwiftUI
import UIKit
import WebKit

@MainActor
@Observable
final class BrowserController: NSObject {
    let linkID: UUID
    let linkName: String
    let initialURL: URL
    let webView: WKWebView

    var progress: Double = 0
    var canGoBack = false
    var isLoading = true
    var controlsVisible = true {
        didSet {
            if controlsVisible != oldValue { applyHeaderInset() }
        }
    }
    var sessionBlocked = 0
    var desktopMode = false
    var pageTitle = ""
    var currentURL: URL
    var loadError: String?
    var blockedHostWarning: String?

    @ObservationIgnored var onDismiss: (() -> Void)?

    @ObservationIgnored private let app: AppModel
    @ObservationIgnored private let bridge: ScriptBridge
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private var warnedBlockedHost = false
    @ObservationIgnored private var didApplyRules = false
    @ObservationIgnored private var isTornDown = false
    @ObservationIgnored private var lastScrollY: CGFloat = 0

    private static let fallbackURL = URL(string: "https://example.com")!
    private static let headerInset: CGFloat = 58
    private static let desktopUserAgent = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Safari/605.1.15"

    var displayHost: String {
        let host = currentURL.host?.lowercased() ?? ""
        guard !host.isEmpty else { return "web" }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    var isSecure: Bool {
        currentURL.scheme?.lowercased() == "https"
    }

    init(link: LinkItem, app: AppModel) {
        let url = link.webURL ?? Self.fallbackURL
        self.linkID = link.id
        self.linkName = link.name
        self.initialURL = url
        self.currentURL = url
        self.app = app

        let bridge = ScriptBridge()
        self.bridge = bridge

        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = true
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.defaultWebpagePreferences.allowsContentJavaScript = true
        configuration.preferences.javaScriptCanOpenWindowsAutomatically = false
        configuration.applicationNameForUserAgent = "LinkDeck/1.0"

        let userContentController = WKUserContentController()
        configuration.userContentController = userContentController

        Self.installScripts(
            on: userContentController,
            blockAds: app.blockAds,
            blockPopups: app.blockPopups
        )
        userContentController.add(bridge, name: "linkdeckStats")
        userContentController.add(bridge, name: "linkdeckMedia")

        var preloadedRules = false
        if app.blockAds, let rules = app.blocker.cachedRuleList(blockPopups: app.blockPopups) {
            userContentController.add(rules)
            preloadedRules = true
        }

        let webView = WKWebView(frame: .zero, configuration: configuration)
        self.webView = webView

        super.init()

        bridge.owner = self
        didApplyRules = preloadedRules

        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.delegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.contentInset.top = Self.headerInset
        webView.scrollView.verticalScrollIndicatorInsets.top = Self.headerInset
        webView.allowsBackForwardNavigationGestures = false
        webView.allowsLinkPreview = true
        webView.isOpaque = false
        webView.backgroundColor = UIColor(Theme.bg)
        webView.scrollView.backgroundColor = UIColor(Theme.bg)
        #if DEBUG
        webView.isInspectable = true
        #endif

        let edgePan = UIScreenEdgePanGestureRecognizer(target: self, action: #selector(handleEdgePan(_:)))
        edgePan.edges = .left
        webView.addGestureRecognizer(edgePan)

        observe(webView)
        installRulesIfNeeded()
        loadInitialPage()
        scheduleAutoHide()
    }

    // MARK: - Navigation

    func reload() {
        if webView.url == nil {
            loadInitialPage()
        } else {
            webView.reload()
        }
    }

    func goBack() {
        if webView.canGoBack {
            webView.goBack()
        }
    }

    func toggleDesktopSite() {
        desktopMode.toggle()
        webView.customUserAgent = desktopMode ? Self.desktopUserAgent : nil
        webView.reload()
    }

    func openInSafari() {
        let url = webView.url ?? currentURL
        guard let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return }
        UIApplication.shared.open(url)
    }

    func removeFromDeck() {
        app.deck.remove(id: linkID)
        app.deck.flush()
    }

    // MARK: - Header visibility

    func showControls() {
        controlsVisible = true
        scheduleAutoHide()
    }

    func hideControls() {
        hideTask?.cancel()
        hideTask = nil
        controlsVisible = false
    }

    /// Keeps the page below the floating header while it is visible, and lets
    /// the content move up when the header fades away.
    private func applyHeaderInset() {
        let inset = controlsVisible ? Self.headerInset : 0
        let scrollView = webView.scrollView
        guard scrollView.contentInset.top != inset else { return }
        let delta = inset - scrollView.contentInset.top
        scrollView.contentInset.top = inset
        scrollView.verticalScrollIndicatorInsets.top = inset
        var offset = scrollView.contentOffset
        offset.y -= delta
        offset.y = max(offset.y, -inset)
        scrollView.setContentOffset(offset, animated: false)
    }

    func scheduleAutoHide(after seconds: Double = 3) {
        hideTask?.cancel()
        hideTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(seconds))
            guard !Task.isCancelled, let self else { return }
            self.controlsVisible = false
            self.hideTask = nil
        }
    }

    // MARK: - Lifecycle

    func tearDown() {
        guard !isTornDown else { return }
        isTornDown = true
        hideTask?.cancel()
        hideTask = nil
        observations.forEach { $0.invalidate() }
        observations.removeAll()
        webView.stopLoading()
        webView.navigationDelegate = nil
        webView.uiDelegate = nil
        webView.scrollView.delegate = nil
        webView.configuration.userContentController.removeAllScriptMessageHandlers()
        UIApplication.shared.isIdleTimerDisabled = false
        app.deck.flush()
    }

    // MARK: - Script bridge

    fileprivate func handleScriptMessage(_ message: WKScriptMessage) {
        switch message.name {
        case "linkdeckStats":
            let count = (message.body as? NSNumber)?.intValue ?? 0
            guard count > 0 else { return }
            sessionBlocked += count
            app.recordBlocked(linkID: linkID, count: count)
        case "linkdeckMedia":
            let playing = (message.body as? NSNumber)?.boolValue ?? false
            UIApplication.shared.isIdleTimerDisabled = playing
        default:
            break
        }
    }

    // MARK: - Setup

    private func loadInitialPage() {
        guard initialURL.scheme?.lowercased().hasPrefix("http") == true else {
            loadError = "This link doesn't have a valid web address."
            isLoading = false
            return
        }
        var request = URLRequest(url: initialURL)
        request.timeoutInterval = 30
        webView.load(request)
    }

    private func installRulesIfNeeded() {
        guard app.blockAds, !didApplyRules else { return }
        Task { [weak self] in
            guard let self else { return }
            guard let rules = await self.app.blocker.contentRuleList(blockPopups: self.app.blockPopups) else {
                return
            }
            guard !self.isTornDown, !self.didApplyRules else { return }
            self.webView.configuration.userContentController.add(rules)
            self.didApplyRules = true
        }
    }

    private func observe(_ webView: WKWebView) {
        observations = [
            webView.observe(\.estimatedProgress, options: [.initial, .new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let webView else { return }
                    self.progress = webView.estimatedProgress
                }
            },
            webView.observe(\.canGoBack, options: [.initial, .new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let webView else { return }
                    self.canGoBack = webView.canGoBack
                }
            },
            webView.observe(\.isLoading, options: [.initial, .new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let webView else { return }
                    self.isLoading = webView.isLoading
                }
            },
            webView.observe(\.url, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let url = webView?.url else { return }
                    self.currentURL = url
                }
            },
            webView.observe(\.title, options: [.new]) { [weak self, weak webView] _, _ in
                Task { @MainActor in
                    guard let self, let title = webView?.title else { return }
                    self.pageTitle = title
                }
            }
        ]
    }

    private static func installScripts(
        on controller: WKUserContentController,
        blockAds: Bool,
        blockPopups: Bool
    ) {
        let flags = """
        window.__linkdeckBlockAds = \(blockAds);
        window.__linkdeckBlockPopups = \(blockPopups);
        """
        controller.addUserScript(WKUserScript(
            source: flags,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))

        if let cosmetic = script(named: "cosmetic") {
            controller.addUserScript(WKUserScript(
                source: cosmetic,
                injectionTime: .atDocumentStart,
                forMainFrameOnly: false
            ))
        }

        controller.addUserScript(WKUserScript(
            source: mediaScript,
            injectionTime: .atDocumentStart,
            forMainFrameOnly: false
        ))
    }

    private static func script(named name: String) -> String? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "js"),
              let source = try? String(contentsOf: url, encoding: .utf8) else {
            return nil
        }
        return source
    }

    private static let mediaScript = """
    (function () {
      if (window.__linkdeckMediaInstalled) return;
      window.__linkdeckMediaInstalled = true;
      var playing = new Set();
      function send() {
        try {
          window.webkit.messageHandlers.linkdeckMedia.postMessage(playing.size > 0);
        } catch (e) { }
      }
      function track(event) {
        var el = event.target;
        if (!el || (el.tagName !== 'VIDEO' && el.tagName !== 'AUDIO')) return;
        if (event.type === 'play' || event.type === 'playing') playing.add(el);
        else playing.delete(el);
        send();
      }
      ['play', 'playing', 'pause', 'ended', 'abort', 'error'].forEach(function (type) {
        document.addEventListener(type, track, true);
      });
      window.addEventListener('pagehide', function () { playing.clear(); send(); }, true);
    })();
    """

    @objc private func handleEdgePan(_ gesture: UIScreenEdgePanGestureRecognizer) {
        guard gesture.state == .ended else { return }
        let translation = gesture.translation(in: webView)
        guard translation.x > 60, abs(translation.x) > abs(translation.y) else { return }
        if webView.canGoBack {
            controlsVisible = true
            webView.goBack()
        } else {
            onDismiss?()
        }
    }
}

// MARK: - WKNavigationDelegate

extension BrowserController: WKNavigationDelegate {
    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction
    ) async -> WKNavigationActionPolicy {
        guard let url = navigationAction.request.url else { return .allow }

        let scheme = url.scheme?.lowercased() ?? ""
        if scheme != "http" && scheme != "https" {
            if scheme == "about" || scheme == "data" || scheme == "blob" {
                return .allow
            }
            await UIApplication.shared.open(url)
            return .cancel
        }

        if app.blockAds,
           navigationAction.targetFrame?.isMainFrame == true,
           !warnedBlockedHost,
           let host = url.host,
           app.blocker.isBlockedHost(host) {
            warnedBlockedHost = true
            blockedHostWarning = host
        }

        return .allow
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        loadError = nil
        isLoading = true
        showControls()
    }

    func webView(_ webView: WKWebView, didCommit navigation: WKNavigation!) {
        if let url = webView.url { currentURL = url }
    }

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isLoading = false
        loadError = nil
        if let url = webView.url { currentURL = url }
        webView.scrollView.contentInset.top = controlsVisible ? Self.headerInset : 0
        scheduleAutoHide()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        handleFailure(error)
    }

    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        isLoading = false
        loadError = "The page stopped responding. Reload to try again."
        showControls()
    }

    private func handleFailure(_ error: Error) {
        let nsError = error as NSError
        guard nsError.code != NSURLErrorCancelled else { return }
        isLoading = false
        loadError = nsError.localizedDescription
        showControls()
    }
}

// MARK: - WKUIDelegate

extension BrowserController: WKUIDelegate {
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        // No popups: new-window links replace the current page.
        if let url = navigationAction.request.url,
           let scheme = url.scheme?.lowercased(),
           scheme == "http" || scheme == "https" {
            webView.load(navigationAction.request)
        }
        return nil
    }
}

// MARK: - UIScrollViewDelegate

extension BrowserController: UIScrollViewDelegate {
    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        let y = scrollView.contentOffset.y
        let delta = y - lastScrollY
        if controlsVisible, y > 20, abs(delta) > 14 {
            hideControls()
        }
        lastScrollY = y
    }
}

// MARK: - Script message bridge

@MainActor
private final class ScriptBridge: NSObject, WKScriptMessageHandler {
    weak var owner: BrowserController?

    func userContentController(
        _ userContentController: WKUserContentController,
        didReceive message: WKScriptMessage
    ) {
        owner?.handleScriptMessage(message)
    }
}
