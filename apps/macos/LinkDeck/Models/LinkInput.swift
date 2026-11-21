import Foundation

enum LinkInput {
    static let maxNameLength = 40

    /// Trims, prepends `https://` when the scheme is missing, and only accepts
    /// http(s) URLs whose host contains a dot.
    static func normalizedURL(from raw: String) -> URL? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        guard !trimmed.contains(where: { $0.isWhitespace }) else { return nil }

        var candidate = trimmed
        if !candidate.contains("://") {
            candidate = "https://" + candidate
        }

        guard let components = URLComponents(string: candidate),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host?.lowercased(),
              !host.isEmpty,
              host.contains("."),
              !host.hasPrefix("."),
              !host.hasSuffix("."),
              !host.contains("..")
        else { return nil }

        return components.url
    }

    /// `www.arte.tv` → `Arte`; drops `www.` and the TLD, capitalises the first label.
    static func suggestedName(for url: URL) -> String {
        guard var host = url.host?.lowercased(), !host.isEmpty else { return "Link" }
        if host.hasPrefix("www.") { host.removeFirst(4) }
        let labels = host.split(separator: ".").filter { !$0.isEmpty }
        guard labels.count > 1 else { return "Link" }

        let words = labels[0].split(whereSeparator: { $0 == "-" || $0 == "_" })
        var name = words
            .map { String($0.prefix(1)).uppercased() + String($0.dropFirst()) }
            .joined(separator: " ")

        if name.isEmpty { name = "Link" }
        return String(name.prefix(maxNameLength))
    }

    static func suggestedName(from raw: String) -> String {
        guard let url = normalizedURL(from: raw) else { return "" }
        return suggestedName(for: url)
    }

    /// Safe for a file name / bundle display name.
    static func sanitizedName(_ raw: String) -> String {
        let forbidden = CharacterSet(charactersIn: "/\\:?%*|\"<>")
        var allowed = ""
        for scalar in raw.unicodeScalars {
            if forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar) {
                allowed.append("-")
            } else {
                allowed.append(Character(scalar))
            }
        }

        var name = allowed
            .split(whereSeparator: { $0.isWhitespace })
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        name = name.trimmingCharacters(in: CharacterSet(charactersIn: "."))

        if name.isEmpty { name = "Link" }
        if name.count > maxNameLength {
            name = String(name.prefix(maxNameLength)).trimmingCharacters(in: .whitespaces)
        }
        return name.isEmpty ? "Link" : name
    }
}
