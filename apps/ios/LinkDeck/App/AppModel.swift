import Foundation
import Observation

@MainActor
@Observable
final class AppModel {
    let deck: DeckStore
    let blocker: AdBlocker

    var blockAds: Bool {
        didSet {
            guard oldValue != blockAds else { return }
            defaults.set(blockAds, forKey: Keys.blockAds)
            if blockAds { prepareBlockerSoon() }
        }
    }

    var blockPopups: Bool {
        didSet {
            guard oldValue != blockPopups else { return }
            defaults.set(blockPopups, forKey: Keys.blockPopups)
            if blockAds { prepareBlockerSoon() }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    private enum Keys {
        static let blockAds = "dev.linkdeck.blockAds"
        static let blockPopups = "dev.linkdeck.blockPopups"
    }

    init() {
        let defaults = UserDefaults.standard
        self.defaults = defaults
        self.deck = DeckStore()
        self.blocker = AdBlocker()
        self.blockAds = defaults.object(forKey: Keys.blockAds) as? Bool ?? true
        self.blockPopups = defaults.object(forKey: Keys.blockPopups) as? Bool ?? true
    }

    init(defaults: UserDefaults, deck: DeckStore, blocker: AdBlocker) {
        self.defaults = defaults
        self.deck = deck
        self.blocker = blocker
        self.blockAds = defaults.object(forKey: Keys.blockAds) as? Bool ?? true
        self.blockPopups = defaults.object(forKey: Keys.blockPopups) as? Bool ?? true
    }

    func prepare() async {
        guard blockAds else { return }
        await blocker.prepare(blockPopups: blockPopups)
    }

    func recordBlocked(linkID: UUID, count: Int) {
        deck.addBlocked(id: linkID, count: count)
    }

    private func prepareBlockerSoon() {
        let popups = blockPopups
        Task { [weak self] in
            guard let self else { return }
            await self.blocker.prepare(blockPopups: popups)
        }
    }
}
