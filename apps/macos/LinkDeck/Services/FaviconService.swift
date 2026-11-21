import AppKit
import Foundation
import os

/// Fetches favicons from DuckDuckGo with a cookie-free session and caches them
/// in memory and on disk. Failures are remembered for the session so a broken
/// icon never turns into a request loop or a broken-image placeholder.
@MainActor
final class FaviconService {
    static let shared = FaviconService()

    private let memory = NSCache<NSString, NSImage>()
    private let dataMemory = NSCache<NSString, NSData>()
    private var inFlight: [String: Task<Data?, Never>] = [:]
    private var failed = Set<String>()

    private let directory: URL
    private let session: URLSession
    private let logger = Logger(subsystem: "dev.linkdeck.mac", category: "favicon")

    init() {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support")
        directory = base.appendingPathComponent("LinkDeck/Favicons", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 12
        configuration.timeoutIntervalForResource = 15
        session = URLSession(configuration: configuration)
    }

    func icon(for host: String) async -> NSImage? {
        let key = host.lowercased()
        guard !key.isEmpty else { return nil }
        if let image = memory.object(forKey: key as NSString) { return image }
        guard let data = await faviconData(for: key), let image = NSImage(data: data) else { return nil }
        memory.setObject(image, forKey: key as NSString)
        return image
    }

    func faviconData(for host: String) async -> Data? {
        let key = host.lowercased()
        guard !key.isEmpty else { return nil }
        if let data = dataMemory.object(forKey: key as NSString) { return data as Data }
        if failed.contains(key) { return nil }
        if let task = inFlight[key] { return await task.value }

        let task = Task { [weak self] in
            await self?.loadData(for: key) ?? nil
        }
        inFlight[key] = task
        let data = await task.value
        inFlight[key] = nil

        if let data {
            dataMemory.setObject(data as NSData, forKey: key as NSString)
        } else {
            failed.insert(key)
        }
        return data
    }

    func clearCache() {
        memory.removeAllObjects()
        dataMemory.removeAllObjects()
        inFlight.removeAll()
        failed.removeAll()
        guard let contents = try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) else { return }
        for file in contents {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func loadData(for host: String) async -> Data? {
        if let disk = diskURL(for: host), let data = try? Data(contentsOf: disk), NSImage(data: data) != nil {
            return data
        }

        guard let encoded = host.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(encoded).ico") else {
            return nil
        }

        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.setValue("image/png,image/x-icon,image/*;q=0.8", forHTTPHeaderField: "Accept")

        do {
            let (data, response) = try await session.data(for: request)
            if let http = response as? HTTPURLResponse, !(200...299).contains(http.statusCode) {
                logger.debug("Favicon HTTP \(http.statusCode) for \(host, privacy: .public)")
                return nil
            }
            guard !data.isEmpty, NSImage(data: data) != nil else { return nil }
            if let disk = diskURL(for: host) {
                try? data.write(to: disk, options: .atomic)
            }
            return data
        } catch {
            logger.debug("Favicon fetch failed for \(host, privacy: .public): \(error.localizedDescription, privacy: .public)")
            return nil
        }
    }

    private func diskURL(for host: String) -> URL? {
        directory.appendingPathComponent("\(StableHash.hex(StableHash.fnv1a(host))).ico")
    }
}
