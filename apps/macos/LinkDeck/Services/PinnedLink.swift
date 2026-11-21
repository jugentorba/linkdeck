import Foundation

/// Marker written into a generated app bundle. Its presence makes LinkDeck
/// launch straight into the saved site instead of showing the deck.
struct PinnedLink: Codable {
    let name: String
    let url: String

    static let fileName = "PinnedLink.json"

    static func readFromMainBundle() -> PinnedLink? {
        guard let resources = Bundle.main.resourceURL else { return nil }
        let url = resources.appendingPathComponent(fileName)
        guard let data = try? Data(contentsOf: url),
              let pinned = try? JSONDecoder().decode(PinnedLink.self, from: data),
              LinkInput.normalizedURL(from: pinned.url) != nil else {
            return nil
        }
        return pinned
    }
}
