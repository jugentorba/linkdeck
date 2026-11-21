import SwiftUI

struct DeckTile: View {
    let link: DeckLink
    let index: Int
    let onOpen: () -> Void
    let onPin: () -> Void
    let onRename: () -> Void
    let onRemove: () -> Void

    @State private var hovering = false
    @State private var appeared = false

    var body: some View {
        Button(action: onOpen) {
            VStack(alignment: .leading, spacing: 0) {
                SiteIcon(name: link.name, host: link.host)

                Text(link.name)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 14)

                Text(link.host)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.top, 2)

                Spacer(minLength: 8)

                if link.blocked > 0 {
                    HStack(spacing: 5) {
                        Image(systemName: "shield.fill")
                            .font(.system(size: 10, weight: .semibold))
                        Text(Format.count(link.blocked))
                            .font(.system(size: 11, weight: .medium))
                    }
                    .foregroundStyle(Theme.success)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(
                        Capsule().fill(Theme.success.opacity(0.10))
                    )
                    .accessibilityLabel("\(Format.count(link.blocked)) blocked")
                }
            }
            .frame(maxWidth: .infinity, minHeight: 124, alignment: .topLeading)
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .fill(hovering ? Theme.surface2 : Theme.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .contentShape(RoundedRectangle(cornerRadius: Theme.tileCorner, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .contextMenu {
            Button("Open") { onOpen() }
            Button("Pin as app") { onPin() }
            Button("Rename…") { onRename() }
            Divider()
            Button("Remove", role: .destructive) { onRemove() }
        }
        .opacity(appeared ? 1 : 0)
        .offset(y: appeared ? 0 : 8)
        .onAppear {
            let delay = min(Double(index), 10) * 0.02
            withAnimation(.easeOut(duration: 0.18).delay(delay)) {
                appeared = true
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityDescription)
        .accessibilityHint("Opens \(link.name)")
        .accessibilityAddTraits(.isButton)
    }

    private var accessibilityDescription: String {
        if link.blocked > 0 {
            return "\(link.name), \(link.host), \(Format.count(link.blocked)) blocked"
        }
        return "\(link.name), \(link.host)"
    }
}
