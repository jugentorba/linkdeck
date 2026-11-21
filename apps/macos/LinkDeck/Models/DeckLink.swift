import Foundation

struct DeckLink: Codable, Identifiable, Hashable {
    var id: UUID
    var name: String
    var url: String
    var addedAt: Date
    var blocked: Int

    init(id: UUID = UUID(), name: String, url: String, addedAt: Date = Date(), blocked: Int = 0) {
        self.id = id
        self.name = name
        self.url = url
        self.addedAt = addedAt
        self.blocked = blocked
    }

    var host: String {
        URL(string: url)?.host ?? url
    }
}
