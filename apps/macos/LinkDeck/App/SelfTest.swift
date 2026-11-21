import AppKit
import Foundation
import WebKit

/// Diagnostics used by `LinkDeck --self-test`. This keeps verification honest
/// without shipping sample links or touching the user's real deck.
@MainActor
enum SelfTest {
    static func run(arguments: [String]) async -> Bool {
        var checks = 0
        var failures: [String] = []

        func check(_ condition: @autoclosure () -> Bool, _ name: String) {
            checks += 1
            if condition() {
                print("  ok   \(name)")
            } else {
                failures.append(name)
                print("  FAIL \(name)")
            }
        }

        print("LinkDeck self-test")

        // URL normalization and name suggestions
        check(LinkInput.normalizedURL(from: "example.com")?.absoluteString == "https://example.com",
              "prepends https://")
        check(LinkInput.normalizedURL(from: "  https://www.arte.tv/info  ")?.absoluteString == "https://www.arte.tv/info",
              "trims and preserves an explicit scheme")
        check(LinkInput.normalizedURL(from: "javascript:alert(1)") == nil, "rejects non-http schemes")
        check(LinkInput.normalizedURL(from: "not a url") == nil, "rejects whitespace")
        check(LinkInput.normalizedURL(from: "https://localhost") == nil, "rejects hosts without a dot")
        check(LinkInput.normalizedURL(from: "https://example.com")?.host == "example.com", "keeps the host")

        if let arte = URL(string: "https://www.arte.tv") {
            check(LinkInput.suggestedName(for: arte) == "Arte", "suggests Arte for www.arte.tv")
        }
        if let news = URL(string: "https://news.ycombinator.com") {
            check(LinkInput.suggestedName(for: news) == "News", "suggests News for news.ycombinator.com")
        }
        check(LinkInput.sanitizedName("A/B: Test?") == "A-B- Test-", "sanitizes bundle names")
        check(LinkInput.sanitizedName("   ") == "Link", "falls back to Link")

        // Storage round-trip
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("LinkDeckStoreTest-\(UUID().uuidString)", isDirectory: true)
        do {
            let store = DeckStore(directory: tempDirectory)
            check(store.links.isEmpty, "starts with no preinstalled links")
            store.add(name: "Example", url: "https://example.com")
            guard let link = store.links.first else {
                failures.append("store failed to add a link")
                print("  FAIL store failed to add a link")
                return finish(checks: checks, failures: failures)
            }
            store.addBlocked(5, linkID: link.id, url: link.url)
            store.flush()

            let reloaded = DeckStore(directory: tempDirectory)
            check(reloaded.links.count == 1, "persists one link")
            check(reloaded.links.first?.blocked == 5, "persists blocked counts")
            check(reloaded.links.first?.name == "Example", "persists the name")
            reloaded.removeAll()
            check(DeckStore(directory: tempDirectory).links.isEmpty, "removeAll persists")
        }
        try? FileManager.default.removeItem(at: tempDirectory)

        // Rule list generation
        let blocklist = BlocklistService()
        check(blocklist.domainCount > 6_000, "loads the shared block list")
        if let sample = blocklist.domains.first {
            check(blocklist.isBlocked(host: "sub.\(sample)"), "suffix-matches subdomains")
            check(!blocklist.isBlocked(host: "not-\(sample).invalid"), "does not match unrelated hosts")
        }
        if let data = BlocklistService.rulesJSON(domains: blocklist.domains),
           let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            check(rules.count == blocklist.domainCount, "creates one rule per domain")
            if let trigger = rules.first?["trigger"] as? [String: Any],
               let types = trigger["resource-type"] as? [String],
               let filter = trigger["url-filter"] as? String {
                check(!types.contains("document"), "never blocks the top-level document")
                check(filter.hasPrefix("^https?://([^/]+\\.)?"), "uses a suffix-match regular expression")
            }
            check(RuleListVerifier.validates(data: data), "rule list decodes as a JSON array of rules")
        } else {
            check(false, "creates a JSON rule list")
        }

        // Pinning (writes to a temporary folder, never ~/Applications)
        if arguments.contains("--pin-test") {
            let root = FileManager.default.temporaryDirectory
                .appendingPathComponent("LinkDeckPinTest-\(UUID().uuidString)", isDirectory: true)
            do {
                let destination = try await PinnedAppBuilder().pin(
                    name: "Report Test",
                    url: "https://example.com",
                    destinationRoot: root
                )
                defer { try? FileManager.default.removeItem(at: root) }

                let marker = destination.appendingPathComponent("Contents/Resources/\(PinnedLink.fileName)")
                let markerData = try? Data(contentsOf: marker)
                let decoded = markerData.flatMap { try? JSONDecoder().decode(PinnedLink.self, from: $0) }
                check(decoded?.url == "https://example.com", "writes PinnedLink.json")
                check(decoded?.name == "Report Test", "writes the pinned name")

                let plistURL = destination.appendingPathComponent("Contents/Info.plist")
                let plistData = try? Data(contentsOf: plistURL)
                let plist = plistData.flatMap {
                    try? PropertyListSerialization.propertyList(from: $0, options: [], format: nil) as? [String: Any]
                }
                check((plist?["CFBundleIdentifier"] as? String)?.hasPrefix("dev.linkdeck.pinned.") == true,
                      "sets a unique bundle identifier")
                check(plist?["CFBundleDisplayName"] as? String == "Report Test", "sets the display name")

                let sourceIcon = Bundle.main.bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
                let destIcon = destination.appendingPathComponent("Contents/Resources/AppIcon.icns")
                let sourceData = try? Data(contentsOf: sourceIcon)
                let destData = try? Data(contentsOf: destIcon)
                check(destData != nil && destData != sourceData, "installs a generated .icns")
                check(SelfTest.codeSignIsValid(destination), "ad-hoc signature verifies")
            } catch {
                check(false, "pin test failed: \(error.localizedDescription)")
            }
        } else {
            print("  --   pin test skipped (pass --pin-test to include it)")
        }

        return finish(checks: checks, failures: failures)
    }

    private static func finish(checks: Int, failures: [String]) -> Bool {
        if failures.isEmpty {
            print("SELFTEST PASSED (\(checks) checks)")
            return true
        }
        print("SELFTEST FAILED (\(failures.count) of \(checks) checks)")
        for failure in failures {
            print("  - \(failure)")
        }
        return false
    }

    private static func codeSignIsValid(_ app: URL) -> Bool {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", app.path]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            return process.terminationStatus == 0
        } catch {
            return false
        }
    }
}

private enum RuleListVerifier {
    static func validates(data: Data) -> Bool {
        guard let rules = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            return false
        }
        return rules.allSatisfy { rule in
            guard let action = rule["action"] as? [String: Any],
                  action["type"] as? String == "block",
                  let trigger = rule["trigger"] as? [String: Any],
                  trigger["url-filter"] is String else {
                return false
            }
            return true
        }
    }
}
