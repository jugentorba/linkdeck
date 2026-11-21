import SwiftUI

struct LinkTileView: View {
    let link: LinkItem
    let index: Int

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                FaviconView(host: link.requestHost, name: link.name, size: 44)

                Spacer(minLength: 4)

                if link.blocked > 0 {
                    shieldPill
                }
            }

            Spacer(minLength: 16)

            Text(link.name)
                .ldFont(15, weight: .semibold, relativeTo: .subheadline)
                .foregroundStyle(Theme.text)
                .lineLimit(2)
                .multilineTextAlignment(.leading)

            Text(link.displayHost)
                .ldFont(12, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .lineLimit(1)
                .truncationMode(.middle)
                .padding(.top, 4)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .contentShape(RoundedRectangle(cornerRadius: Theme.tileRadius, style: .continuous))
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : (reduceMotion ? 0 : 8))
        .onAppear {
            guard !appeared else { return }
            withAnimation(
                reduceMotion
                    ? nil
                    : .easeOut(duration: 0.18).delay(Double(min(index, 8)) * 0.025)
            ) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityText)
        .accessibilityHint("Opens in LinkDeck")
        .accessibilityAddTraits(.isButton)
    }

    private var shieldPill: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .font(.system(size: 9, weight: .semibold))
            Text(Format.count(link.blocked))
                .ldFont(11, weight: .semibold, relativeTo: .caption2)
        }
        .foregroundStyle(Theme.success)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(Theme.success.opacity(0.12), in: Capsule())
        .accessibilityLabel("\(link.blocked) blocked")
    }

    private var accessibilityText: String {
        if link.blocked > 0 {
            return "\(link.name), \(link.displayHost), \(Format.count(link.blocked)) blocked"
        }
        return "\(link.name), \(link.displayHost)"
    }
}
