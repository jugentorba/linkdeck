import Foundation
import os
import WebKit

/// Compiles and caches the bundled suffix-match blocklist as WKContentRuleLists.
///
/// WKContentRuleList cannot report how many requests it blocked, so the deck's
/// counter is fed by the cosmetic/popup script bridge. Network blocking itself
/// happens silently in WebKit.
@MainActor
final class AdBlocker {
    private let logger = Logger(subsystem: "dev.linkdeck.app", category: "AdBlocker")
    private let store: WKContentRuleListStore?
    private let domains: Set<String>
    private let entries: [String]
    private let listHash: String

    private var cachedLists: [String: WKContentRuleList] = [:]
    private var compileTasks: [String: Task<WKContentRuleList?, Never>] = [:]

    init(bundle: Bundle = .main) {
        self.store = WKContentRuleListStore.default()
        let url = bundle.url(forResource: "blocklist", withExtension: "txt")
        let text = url.flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? ""
        let contentsHash = StableHash.fnv1a(text)

        var seen = Set<String>()
        var parsed: [String] = []
        for rawLine in text.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !line.isEmpty, !line.hasPrefix("#") else { continue }
            let domain = line.lowercased()
            guard domain.contains("."), !domain.contains(" "),
                  domain.rangeOfCharacter(from: CharacterSet(charactersIn: "/:@?&=#")) == nil else {
                continue
            }
            if seen.insert(domain).inserted {
                parsed.append(domain)
            }
        }

        self.entries = parsed
        self.domains = seen
        self.listHash = String(contentsHash, radix: 16)
        logger.info("Loaded \(parsed.count, privacy: .public) blocklist domains")
    }

    var domainCount: Int { entries.count }

    /// Returns the compiled list for the current popup preference, loading from
    /// WebKit's on-disk cache or compiling once if needed. Never throws.
    func contentRuleList(blockPopups: Bool) async -> WKContentRuleList? {
        guard !entries.isEmpty else { return nil }
        let key = cacheKey(blockPopups: blockPopups)
        if let cached = cachedLists[key] { return cached }
        if let task = compileTasks[key] { return await task.value }

        let task = Task<WKContentRuleList?, Never> { [weak self] in
            guard let self else { return nil }
            return await self.loadOrCompile(key: key, blockPopups: blockPopups)
        }
        compileTasks[key] = task
        let list = await task.value
        compileTasks[key] = nil
        if let list { cachedLists[key] = list }
        return list
    }

    func cachedRuleList(blockPopups: Bool) -> WKContentRuleList? {
        cachedLists[cacheKey(blockPopups: blockPopups)]
    }

    func prepare(blockPopups: Bool) async {
        _ = await contentRuleList(blockPopups: blockPopups)
    }

    /// Suffix match: host == entry or host ends in "." + entry.
    func isBlockedHost(_ host: String) -> Bool {
        var candidate = host.lowercased()
        if candidate.hasSuffix(".") { candidate.removeLast() }
        while !candidate.isEmpty {
            if domains.contains(candidate) { return true }
            guard let dot = candidate.firstIndex(of: ".") else { return false }
            candidate = String(candidate[candidate.index(after: dot)...])
        }
        return false
    }

    private func cacheKey(blockPopups: Bool) -> String {
        "dev.linkdeck.blocklist.\(listHash).\(blockPopups ? "popups" : "plain")"
    }

    private func loadOrCompile(key: String, blockPopups: Bool) async -> WKContentRuleList? {
        if let cached = await lookUp(key) {
            logger.info("Using cached content rule list \(key, privacy: .public)")
            return cached
        }

        let rules = makeRules(blockPopups: blockPopups)
        guard !rules.isEmpty,
              JSONSerialization.isValidJSONObject(rules),
              let data = try? JSONSerialization.data(withJSONObject: rules),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Could not encode the content rule list")
            return nil
        }

        logger.info("Compiling \(rules.count, privacy: .public) content blocker rules (popups: \(blockPopups, privacy: .public))")
        let start = Date()
        let list = await compile(json, identifier: key)
        if list != nil {
            let seconds = Date().timeIntervalSince(start)
            logger.info("Compiled blocklist in \(seconds, format: .fixed(precision: 2), privacy: .public)s")
        } else {
            logger.error("Content rule list compilation failed; continuing without network blocking")
        }
        return list
    }

    private func lookUp(_ identifier: String) async -> WKContentRuleList? {
        guard let store = self.store else { return nil }
        return await withCheckedContinuation { continuation in
            store.lookUpContentRuleList(forIdentifier: identifier) { list, error in
                if let error {
                    // A cache miss is normal; only surface unusual errors.
                    if (error as NSError).code != WKError.contentRuleListStoreLookUpFailed.rawValue {
                        NSLog("LinkDeck blocklist lookup: \(error.localizedDescription)")
                    }
                }
                continuation.resume(returning: list)
            }
        }
    }

    private func compile(_ json: String, identifier: String) async -> WKContentRuleList? {
        guard let store = self.store else { return nil }
        return await withCheckedContinuation { continuation in
            store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error {
                    NSLog("LinkDeck blocklist compile: \(error.localizedDescription)")
                }
                continuation.resume(returning: list)
            }
        }
    }

    private func makeRules(blockPopups: Bool) -> [[String: Any]] {
        var resourceTypes = [
            "image", "style-sheet", "script", "font", "raw", "svg-document", "media",
            // Third-party iframes are the usual ad container. Top-level
            // navigation is first-party and still passes because of load-type.
            "document"
        ]
        if blockPopups { resourceTypes.append("popup") }

        return entries.map { domain in
            let escaped = NSRegularExpression.escapedPattern(for: domain)
            return [
                "trigger": [
                    // WebKit's content-blocker regex engine does not support
                    // alternation, so the trailing boundary is the / or : that
                    // every real request URL has after the host. (The `$` arm of
                    // the usual `([/:]|$)` idiom is unsupported here.)
                    "url-filter": "^https?://([^/]+\\.)?\(escaped)([/:])",
                    "url-filter-is-case-sensitive": false,
                    "load-type": ["third-party"],
                    "resource-type": resourceTypes
                ],
                "action": ["type": "block"]
            ]
        }
    }
}
