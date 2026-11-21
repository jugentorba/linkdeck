import Foundation

enum Format {
    private static let groupedCount: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = true
        formatter.groupingSize = 3
        formatter.locale = Locale(identifier: "en_US")
        return formatter
    }()

    /// "1,284" — matches the product copy regardless of device locale.
    static func count(_ value: Int) -> String {
        groupedCount.string(from: NSNumber(value: value)) ?? "\(value)"
    }
}
