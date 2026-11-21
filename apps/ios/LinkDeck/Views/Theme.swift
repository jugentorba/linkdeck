import SwiftUI

/// Design tokens from shared/design.md.
enum Theme {
    static let bg = Color(hex: 0x0B0D10)
    static let surface = Color(hex: 0x14171C)
    static let surface2 = Color(hex: 0x1C2027)
    static let stroke = Color(hex: 0x272D36)
    static let text = Color(hex: 0xF2F5F7)
    static let muted = Color(hex: 0x98A2B3)
    static let muted2 = Color(hex: 0x6B7482)
    static let accent = Color(hex: 0x7C6BFF)
    static let accent2 = Color(hex: 0xA78BFA)
    static let success = Color(hex: 0x34D399)
    static let danger = Color(hex: 0xF87171)

    static let screenPadding: CGFloat = 20
    static let tileRadius: CGFloat = 20
    static let gridGap: CGFloat = 12
}

extension Color {
    init(hex: UInt32, alpha: Double = 1) {
        self.init(
            .sRGB,
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255,
            opacity: alpha
        )
    }
}

/// Scales a precise point size with Dynamic Type.
private struct ScaledFontModifier: ViewModifier {
    @ScaledMetric private var size: CGFloat
    private let weight: Font.Weight

    init(size: CGFloat, weight: Font.Weight, relativeTo style: Font.TextStyle) {
        _size = ScaledMetric(wrappedValue: size, relativeTo: style)
        self.weight = weight
    }

    func body(content: Content) -> some View {
        content.font(.system(size: size, weight: weight))
    }
}

extension View {
    func ldFont(
        _ size: CGFloat,
        weight: Font.Weight = .regular,
        relativeTo style: Font.TextStyle = .body
    ) -> some View {
        modifier(ScaledFontModifier(size: size, weight: weight, relativeTo: style))
    }

    func ldSurfaceCard(cornerRadius: CGFloat = 20) -> some View {
        background(Theme.surface)
            .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .strokeBorder(Theme.stroke, lineWidth: 1)
            }
    }
}

extension Font {
    static func ld(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight)
    }
}

/// FNV-1a is stable across launches, unlike Swift's Hasher.
enum StableHash {
    static func fnv1a(_ string: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in string.utf8 {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        return hash
    }
}
