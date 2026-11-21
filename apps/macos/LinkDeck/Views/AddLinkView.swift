import SwiftUI

struct AddLinkView: View {
    @ObservedObject var store: DeckStore
    @Environment(\.dismiss) private var dismiss

    @State private var url = ""
    @State private var name = ""
    @State private var errorMessage: String?
    @FocusState private var urlFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Add a link")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.text)
                    Text("Anything with a web address works.")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
                IconButton(systemName: "xmark", label: "Close", action: { dismiss() })
            }

            fieldLabel("URL")
                .padding(.top, 24)

            TextField(
                "",
                text: $url,
                prompt: Text("https://example.com").foregroundColor(Theme.muted2)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .focused($urlFocused)
            .onSubmit(add)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(errorMessage == nil ? Theme.stroke : Theme.danger, lineWidth: 1)
            )
            .accessibilityLabel("URL")
            .padding(.top, 7)
            .onChange(of: url) { _, newValue in
                errorMessage = nil
                if name == LinkInput.suggestedName(from: url) || name.isEmpty {
                    name = LinkInput.suggestedName(from: newValue)
                }
            }

            if let errorMessage {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.circle.fill")
                    Text(errorMessage)
                }
                .font(.system(size: 12))
                .foregroundStyle(Theme.danger)
                .padding(.top, 8)
                .accessibilityLabel("Error: \(errorMessage)")
            }

            fieldLabel("Name")
                .padding(.top, 18)

            TextField(
                "",
                text: $name,
                prompt: Text("Optional").foregroundColor(Theme.muted2)
            )
            .textFieldStyle(.plain)
            .font(.system(size: 15))
            .foregroundStyle(Theme.text)
            .onSubmit(add)
            .padding(.horizontal, 14)
            .frame(height: 44)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Theme.surface2)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
            .accessibilityLabel("Name")
            .onChange(of: name) { _, newValue in
                if newValue.count > LinkInput.maxNameLength {
                    name = String(newValue.prefix(LinkInput.maxNameLength))
                }
            }
            .padding(.top, 7)

            HStack(spacing: 10) {
                Spacer()
                Button("Cancel") { dismiss() }
                    .buttonStyle(SecondaryButtonStyle())
                    .keyboardShortcut(.cancelAction)
                Button("Add to deck", action: add)
                    .buttonStyle(PrimaryButtonStyle())
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.top, 26)
        }
        .padding(24)
        .frame(width: 480)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
        .onAppear {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                urlFocused = true
            }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.system(size: 12, weight: .semibold))
            .tracking(1.2)
            .foregroundStyle(Theme.muted2)
    }

    private func add() {
        guard let normalized = LinkInput.normalizedURL(from: url) else {
            errorMessage = "Enter a web address, like example.com."
            urlFocused = true
            return
        }

        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalName = trimmedName.isEmpty ? LinkInput.suggestedName(for: normalized) : trimmedName
        store.add(name: finalName, url: normalized.absoluteString)
        dismiss()
    }
}
