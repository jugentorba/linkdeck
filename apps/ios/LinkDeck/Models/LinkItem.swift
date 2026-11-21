import Foundation

struct LinkItem: Identifiable, Codable, Hashable, Sendable {
    let id: UUID
    var name: String
    var url: String
    var addedAt: Date
    var blocked: Int

    init(
        id: UUID = UUID(),
        name: String,
        url: String,
        addedAt: Date = .now,
        blocked: Int = 0
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.addedAt = addedAt
        self.blocked = blocked
    }

    var webURL: URL? {
        guard let url = URL(string: url),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// Host used for the favicon request and for matching.
    var requestHost: String {
        URLComponents(string: url)?.host?.lowercased() ?? ""
    }

    /// Host shown in the UI, without the leading "www.".
    var displayHost: String {
        let host = requestHost
        guard !host.isEmpty else { return url }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    static func suggestedName(forHost host: String) -> String {
        var host = host.lowercased()
        if host.hasPrefix("www.") { host.removeFirst(4) }
        guard let first = host.split(separator: ".").first, !first.isEmpty else {
            return "Untitled"
        }
        let cleaned = first
            .replacingOccurrences(of: "-", with: " ")
            .replacingOccurrences(of: "_", with: " ")
        return cleaned.capitalized
    }

    static func suggestedName(forURLString string: String) -> String {
        guard let result = try? URLNormalizer.normalize(string) else { return "" }
        return suggestedName(forHost: result.host)
    }

    static func sanitizedName(_ name: String, fallback: String) -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? fallback : trimmed
        return String(base.prefix(40))
    }
}

enum URLValidationError: Error, Equatable {
    case empty
    case unsupportedScheme
    case invalid

    var message: String {
        switch self {
        case .empty:
            return "Enter a web address."
        case .unsupportedScheme:
            return "Only http and https links work here."
        case .invalid:
            return "That doesn't look like a web address. Try example.com."
        }
    }
}

enum URLNormalizer {
    struct Result: Equatable, Sendable {
        let url: URL
        let host: String
    }

    static func normalize(_ raw: String) throws(URLValidationError) -> Result {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw .empty }
        guard trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil else {
            throw .invalid
        }

        let candidate = trimmed.contains("://") ? trimmed : "https://" + trimmed
        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased() else {
            throw .invalid
        }
        guard scheme == "http" || scheme == "https" else {
            throw .unsupportedScheme
        }
        guard let host = components.host?.lowercased(),
              !host.isEmpty,
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              host.contains(".") else {
            throw .invalid
        }
        guard let url = components.url else { throw .invalid }

        return Result(url: url, host: host)
    }
}
