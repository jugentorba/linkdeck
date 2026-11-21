import Foundation
import WebKit
import os

/// Loads the suffix-matched host list and compiles it into a cached
/// `WKContentRuleList`. The list is applied to every web view.
@MainActor
final class BlocklistService {
    private(set) var domains: [String] = []
    private var domainSet: Set<String> = []

    private let logger = Logger(subsystem: "dev.linkdeck.mac", category: "blocklist")
    private let ruleStore: WKContentRuleListStore?
    private let identifier: String
    private var cachedRuleList: WKContentRuleList?
    private var compileTask: Task<WKContentRuleList?, Never>?

    init(bundle: Bundle = .main) {
        ruleStore = WKContentRuleListStore.default()

        var loaded: [String] = []
        var seen = Set<String>()
        var versionSeed = "empty"

        if let url = bundle.url(forResource: "blocklist", withExtension: "txt"),
           let text = try? String(contentsOf: url, encoding: .utf8) {
            for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty, !line.hasPrefix("#") else { continue }
                let domain = line.lowercased()
                if seen.insert(domain).inserted {
                    loaded.append(domain)
                }
            }
            if let data = text.data(using: .utf8) {
                versionSeed = StableHash.hex(StableHash.fnv1a(data))
            }
        } else {
            logger.error("blocklist.txt is missing from the app bundle")
        }

        domains = loaded
        domainSet = seen
        identifier = "linkdeck-blocklist-\(versionSeed)-\(loaded.count)"
        logger.info("Loaded \(loaded.count) blocked domains")
    }

    var domainCount: Int { domains.count }

    func isBlocked(host: String) -> Bool {
        guard !domainSet.isEmpty else { return false }
        let normalized = host.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "."))
        guard !normalized.isEmpty else { return false }
        if domainSet.contains(normalized) { return true }

        var labels = normalized.split(separator: ".")
        while labels.count > 1 {
            labels.removeFirst()
            if domainSet.contains(labels.joined(separator: ".")) { return true }
        }
        return false
    }

    func ruleList() async -> WKContentRuleList? {
        if let cachedRuleList { return cachedRuleList }
        if let compileTask { return await compileTask.value }

        let task = Task { [weak self] in
            await self?.compile() ?? nil
        }
        compileTask = task
        let result = await task.value
        cachedRuleList = result
        compileTask = nil
        return result
    }

    private func compile() async -> WKContentRuleList? {
        guard !domains.isEmpty else {
            logger.error("Refusing to compile an empty block list")
            return nil
        }
        guard let ruleStore else {
            logger.error("WKContentRuleListStore is unavailable")
            return nil
        }
        guard let data = Self.rulesJSON(domains: domains),
              let json = String(data: data, encoding: .utf8) else {
            logger.error("Could not encode the content rule list")
            return nil
        }

        do {
            if let existing = try await lookUp(ruleStore: ruleStore) {
                logger.info("Using cached rule list \(self.identifier, privacy: .public)")
                return existing
            }
        } catch {
            // A missing rule list legitimately reports an error; compile it below.
            logger.debug("Rule list lookup miss: \(error.localizedDescription, privacy: .public)")
        }

        do {
            let list = try await compile(ruleStore: ruleStore, json: json)
            logger.info("Compiled \(self.domains.count) content rules (\(data.count) bytes)")
            return list
        } catch {
            logger.error("Content rule list compilation failed: \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func lookUp(ruleStore: WKContentRuleListStore) async throws -> WKContentRuleList? {
        try await withCheckedThrowingContinuation { continuation in
            ruleStore.lookUpContentRuleList(forIdentifier: identifier) { list, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: list)
                }
            }
        }
    }

    private func compile(ruleStore: WKContentRuleListStore, json: String) async throws -> WKContentRuleList {
        try await withCheckedThrowingContinuation { continuation in
            ruleStore.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json) { list, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let list {
                    continuation.resume(returning: list)
                } else {
                    continuation.resume(throwing: BlocklistError.emptyCompilation)
                }
            }
        }
    }

    enum BlocklistError: LocalizedError {
        case emptyCompilation

        var errorDescription: String? {
            "The content blocker returned no rule list."
        }
    }

    /// Suffix match, case-insensitive, with the top-level document explicitly
    /// excluded so the app itself can never be blocked.
    static func rulesJSON(domains: [String]) -> Data? {
        let resourceTypes = ["image", "style-sheet", "script", "font", "media", "raw", "svg-document", "popup"]
        let rules: [[String: Any]] = domains.compactMap { domain in
            let pattern = regexEscape(domain)
            guard !pattern.isEmpty else { return nil }
            return [
                "trigger": [
                    "url-filter": "^https?://([^/]+\\.)?\(pattern)([/:]|$)",
                    "url-filter-is-case-sensitive": false,
                    "resource-type": resourceTypes
                ],
                "action": ["type": "block"]
            ]
        }
        guard rules.count == domains.count else { return nil }
        return try? JSONSerialization.data(withJSONObject: rules, options: [])
    }

    private static func regexEscape(_ value: String) -> String {
        var result = ""
        for character in value {
            if character.isLetter || character.isNumber || character == "-" {
                result.append(character)
            } else {
                result.append("\\")
                result.append(character)
            }
        }
        return result
    }
}
