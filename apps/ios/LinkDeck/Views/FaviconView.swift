import SwiftUI
import UIKit

struct FaviconView: View {
    let host: String
    let name: String
    let size: CGFloat
    var cornerRadius: CGFloat = 12

    @State private var image: UIImage?

    var body: some View {
        ZStack {
            LetterTile(host: host, name: name)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
                    .transition(.opacity)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(Color.white.opacity(0.06), lineWidth: 1)
        }
        .task(id: host) {
            guard !host.isEmpty else { return }
            let loaded = await FaviconLoader.shared.image(forHost: host)
            if let loaded {
                withAnimation(.easeOut(duration: 0.15)) { image = loaded }
            }
        }
        .accessibilityHidden(true)
    }
}

private struct LetterTile: View {
    let host: String
    let name: String

    private var letter: String {
        let source = name.isEmpty ? host : name
        guard let character = source.first(where: { $0.isLetter || $0.isNumber }) else {
            return "•"
        }
        return String(character).uppercased()
    }

    private var colors: [Color] {
        let hash = StableHash.fnv1a(host.isEmpty ? name : host)
        let hue = Double(hash % 360) / 360
        let secondHue = (hue + 0.09).truncatingRemainder(dividingBy: 1)
        return [
            Color(hue: hue, saturation: 0.52, brightness: 0.56),
            Color(hue: secondHue, saturation: 0.62, brightness: 0.34)
        ]
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            Text(letter)
                .font(.system(size: 20, weight: .bold, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
