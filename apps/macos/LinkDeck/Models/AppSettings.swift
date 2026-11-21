import Combine
import Foundation

@MainActor
final class AppSettings: ObservableObject {
    @Published var blockAds: Bool {
        didSet { defaults.set(blockAds, forKey: Keys.blockAds) }
    }

    @Published var blockPopups: Bool {
        didSet { defaults.set(blockPopups, forKey: Keys.blockPopups) }
    }

    private let defaults: UserDefaults

    private enum Keys {
        static let blockAds = "blockAds"
        static let blockPopups = "blockPopups"
        static let warnedHosts = "warnedHosts"
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        blockAds = defaults.object(forKey: Keys.blockAds) as? Bool ?? true
        blockPopups = defaults.object(forKey: Keys.blockPopups) as? Bool ?? true
    }

    func hasWarned(host: String) -> Bool {
        warnedHosts.contains(host.lowercased())
    }

    func markWarned(host: String) {
        var hosts = warnedHosts
        hosts.insert(host.lowercased())
        defaults.set(Array(hosts).sorted(), forKey: Keys.warnedHosts)
    }

    private var warnedHosts: Set<String> {
        Set(defaults.stringArray(forKey: Keys.warnedHosts) ?? [])
    }
}
