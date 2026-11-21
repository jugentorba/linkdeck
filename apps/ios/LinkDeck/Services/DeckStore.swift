import Foundation
import Observation
import os

@MainActor
@Observable
final class DeckStore {
    private(set) var links: [LinkItem] = []

    @ObservationIgnored private let fileURL: URL
    @ObservationIgnored private let logger = Logger(subsystem: "dev.linkdeck.app", category: "DeckStore")
    @ObservationIgnored private var saveTask: Task<Void, Never>?

    init() {
        let fileManager = FileManager.default
        let base = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
        try? fileManager.createDirectory(at: base, withIntermediateDirectories: true)
        self.fileURL = base.appendingPathComponent("deck.json", isDirectory: false)
        load()
    }

    init(fileURL: URL) {
        self.fileURL = fileURL
        load()
    }

    @discardableResult
    func add(name: String, url: String) -> LinkItem {
        let fallback = LinkItem.suggestedName(forURLString: url)
        let item = LinkItem(
            name: LinkItem.sanitizedName(name, fallback: fallback),
            url: url
        )
        links.insert(item, at: 0)
        writeNow()
        return item
    }

    func rename(id: UUID, name: String) {
        guard let index = links.firstIndex(where: { $0.id == id }) else { return }
        let existing = links[index]
        links[index].name = LinkItem.sanitizedName(name, fallback: existing.name)
        writeNow()
    }

    func remove(id: UUID) {
        links.removeAll { $0.id == id }
        writeNow()
    }

    func removeAll() {
        links.removeAll()
        writeNow()
    }

    /// Adds to an app's cumulative blocked count and saves on a short debounce.
    func addBlocked(id: UUID, count: Int) {
        guard count > 0, let index = links.firstIndex(where: { $0.id == id }) else { return }
        links[index].blocked += count
        scheduleWrite()
    }

    func resetBlockedCounts() {
        guard links.contains(where: { $0.blocked > 0 }) else { return }
        for index in links.indices {
            links[index].blocked = 0
        }
        writeNow()
    }

    var totalBlocked: Int {
        links.reduce(0) { $0 + $1.blocked }
    }

    /// Writes any pending debounced change immediately (scene background, teardown).
    func flush() {
        saveTask?.cancel()
        saveTask = nil
        writeNow()
    }

    private func scheduleWrite() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard !Task.isCancelled, let self else { return }
            self.saveTask = nil
            self.writeNow()
        }
    }

    private func load() {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return }
        do {
            let data = try Data(contentsOf: fileURL)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            links = try decoder.decode([LinkItem].self, from: data)
        } catch {
            logger.error("Could not read deck.json: \(error.localizedDescription, privacy: .public)")
            links = []
        }
    }

    private func writeNow() {
        do {
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            encoder.dateEncodingStrategy = .iso8601
            let data = try encoder.encode(links)
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: fileURL, options: .atomic)
        } catch {
            logger.error("Could not write deck.json: \(error.localizedDescription, privacy: .public)")
        }
    }
}
