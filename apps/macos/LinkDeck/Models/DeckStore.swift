import Combine
import Foundation
import os

@MainActor
final class DeckStore: ObservableObject {
    @Published private(set) var links: [DeckLink] = []

    private let fileURL: URL
    private let logger = Logger(subsystem: "dev.linkdeck.mac", category: "store")
    private var pendingSave: DispatchWorkItem?
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let base = directory ?? Self.defaultDirectory()
        fileURL = base.appendingPathComponent("deck.json")

        encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]

        decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        load()
    }

    static func defaultDirectory() -> URL {
        let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        return support.appendingPathComponent("LinkDeck", isDirectory: true)
    }

    var totalBlocked: Int {
        links.reduce(0) { $0 + $1.blocked }
    }

    func link(withURL url: String) -> DeckLink? {
        links.first { $0.url == url }
    }

    @discardableResult
    func add(name: String, url: String) -> DeckLink {
        let trimmed = String(name.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LinkInput.maxNameLength))
        let link = DeckLink(name: trimmed.isEmpty ? "Link" : trimmed, url: url)
        links.append(link)
        saveNow()
        return link
    }

    func rename(id: UUID, to newName: String) {
        let trimmed = String(newName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(LinkInput.maxNameLength))
        guard !trimmed.isEmpty, let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index].name = trimmed
        saveNow()
    }

    func remove(id: UUID) {
        links.removeAll { $0.id == id }
        saveNow()
    }

    func remove(id: UUID, url: String) {
        links.removeAll { $0.id == id || $0.url == url }
        saveNow()
    }

    func removeAll() {
        links.removeAll()
        saveNow()
    }

    /// Adds blocked events to the deck link, matching by id first and URL second
    /// (a pinned copy has its own id but should feed the same deck entry).
    func addBlocked(_ count: Int, linkID: UUID, url: String) {
        guard count > 0 else { return }
        if let index = links.firstIndex(where: { $0.id == linkID || $0.url == url }) {
            links[index].blocked += count
            scheduleSave()
        }
    }

    func resetBlockedCounts() {
        guard !links.isEmpty else { return }
        for index in links.indices { links[index].blocked = 0 }
        saveNow()
    }

    func flush() {
        pendingSave?.cancel()
        pendingSave = nil
        saveNow()
    }

    private func load() {
        let manager = FileManager.default
        try? manager.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        guard manager.fileExists(atPath: fileURL.path) else { return }

        do {
            let data = try Data(contentsOf: fileURL)
            links = try decoder.decode([DeckLink].self, from: data)
        } catch {
            logger.error("Could not read deck.json: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func scheduleSave() {
        pendingSave?.cancel()
        let work = DispatchWorkItem { [weak self] in
            self?.saveNow()
        }
        pendingSave = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6, execute: work)
    }

    private func saveNow() {
        do {
            try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            let data = try encoder.encode(links)
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write deck.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
