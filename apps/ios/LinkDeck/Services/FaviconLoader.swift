import SwiftUI
import UIKit

/// Fetches favicons from DuckDuckGo with an in-memory and on-disk cache.
/// Requests carry no cookies and no referrer.
@MainActor
final class FaviconLoader {
    static let shared = FaviconLoader()

    private let memoryCache = NSCache<NSString, UIImage>()
    private let diskCache: URLCache
    private let session: URLSession

    private init() {
        let cache = URLCache(
            memoryCapacity: 8 * 1024 * 1024,
            diskCapacity: 64 * 1024 * 1024,
            diskPath: "linkdeck-favicons"
        )
        diskCache = cache

        let configuration = URLSessionConfiguration.default
        configuration.urlCache = cache
        configuration.requestCachePolicy = .returnCacheDataElseLoad
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.httpShouldUsePipelining = true
        configuration.timeoutIntervalForRequest = 10
        configuration.timeoutIntervalForResource = 15
        configuration.httpAdditionalHeaders = [
            "Accept": "image/*",
            "User-Agent": "LinkDeck/1.0 (iOS)"
        ]
        session = URLSession(configuration: configuration)
        memoryCache.countLimit = 256
    }

    func image(forHost host: String) async -> UIImage? {
        guard !host.isEmpty else { return nil }
        let key = host as NSString
        if let cached = memoryCache.object(forKey: key) { return cached }

        guard let encodedHost = host.addingPercentEncoding(withAllowedCharacters: .urlHostAllowed),
              let url = URL(string: "https://icons.duckduckgo.com/ip3/\(encodedHost).ico") else {
            return nil
        }

        var request = URLRequest(url: url, cachePolicy: .returnCacheDataElseLoad, timeoutInterval: 10)
        request.httpShouldHandleCookies = false
        request.setValue("image/*", forHTTPHeaderField: "Accept")
        request.setValue(nil, forHTTPHeaderField: "Referer")

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  200..<300 ~= http.statusCode,
                  !data.isEmpty,
                  let image = UIImage(data: data),
                  image.size.width > 0,
                  image.size.height > 0 else {
                return nil
            }
            memoryCache.setObject(image, forKey: key, cost: data.count)
            return image
        } catch {
            return nil
        }
    }

    func clear() {
        memoryCache.removeAllObjects()
        diskCache.removeAllCachedResponses()
    }
}
