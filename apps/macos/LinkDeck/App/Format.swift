import Foundation

enum Format {
    private static let decimal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.locale = Locale(identifier: "en_US")
        formatter.usesGroupingSeparator = true
        formatter.groupingSeparator = ","
        return formatter
    }()

    static func count(_ value: Int) -> String {
        decimal.string(from: NSNumber(value: value)) ?? String(value)
    }

    static func links(_ count: Int) -> String {
        count == 1 ? "1 link" : "\(Format.count(count)) links"
    }

    static func deckSubtitle(links: Int, blocked: Int) -> String {
        "\(Format.links(links)) · \(Format.count(blocked)) blocked"
    }
}
