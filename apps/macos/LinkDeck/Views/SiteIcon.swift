import AppKit
import SwiftUI

/// Favicon with a deterministic letter-tile fallback. The letter tile is shown
/// while loading and whenever the favicon cannot be fetched or decoded.
struct SiteIcon: View {
    let name: String
    let host: String
    var size: CGFloat = 44

    @State private var image: NSImage?

    private var letter: String {
        if let character = name.first(where: { $0.isLetter || $0.isNumber }) {
            return String(character).uppercased()
        }
        if let character = host.first(where: { $0.isLetter || $0.isNumber }) {
            return String(character).uppercased()
        }
        return "•"
    }

    private var gradient: LinearGradient {
        let hue = Double(StableHash.fnv1a(host) % 360) / 360
        return LinearGradient(
            colors: [
                Color(hue: hue, saturation: 0.55, brightness: 0.62),
                Color(hue: (hue + 0.09).truncatingRemainder(dividingBy: 1), saturation: 0.62, brightness: 0.38)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    var body: some View {
        ZStack {
            if let image {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface2)
                Image(nsImage: image)
                    .resizable()
                    .scaledToFit()
                    .padding(5)
            } else {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(gradient)
                Text(letter)
                    .font(.system(size: size * 0.42, weight: .semibold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .task(id: host) {
            image = await FaviconService.shared.icon(for: host)
        }
        .accessibilityHidden(true)
    }
}
