import SwiftUI

struct AddLinkSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var urlText = ""
    @State private var nameText = ""
    @State private var errorMessage: String?
    @State private var previousSuggestion = ""

    @FocusState private var focusedField: Field?

    private enum Field {
        case url
        case name
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                urlField
                nameField

                if let errorMessage {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Image(systemName: "exclamationmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                        Text(errorMessage)
                            .ldFont(13, relativeTo: .footnote)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .foregroundStyle(Theme.danger)
                    .transition(.opacity)
                }
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 28)
        }
        .scrollDismissesKeyboard(.interactively)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            addButton
        }
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.bg)
        .onAppear {
            Task {
                try? await Task.sleep(for: .milliseconds(350))
                focusedField = .url
            }
        }
        .onChange(of: urlText) { _, newValue in
            if errorMessage != nil { errorMessage = nil }
            let suggestion = LinkItem.suggestedName(forURLString: newValue)
            if nameText.isEmpty || nameText == previousSuggestion {
                nameText = suggestion
            }
            previousSuggestion = suggestion
        }
        .onChange(of: nameText) { _, newValue in
            if newValue.count > 40 {
                nameText = String(newValue.prefix(40))
            }
        }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Add a link")
                    .ldFont(28, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(Theme.text)
                Text("Anything with a web address works.")
                    .ldFont(14, relativeTo: .subheadline)
                    .foregroundStyle(Theme.muted)
            }

            Spacer(minLength: 8)

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Theme.muted)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface2, in: Circle())
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityIdentifier("closeAddSheet")
            .accessibilityLabel("Close")
        }
        .padding(.top, 12)
    }

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 8) {
            fieldLabel("URL")

            TextField("example.com", text: $urlText)
                .ldFont(15, relativeTo: .body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .textContentType(.URL)
                .keyboardType(.URL)
                .submitLabel(.next)
                .focused($focusedField, equals: .url)
                .accessibilityIdentifier("urlField")
                .onSubmit { focusedField = .name }
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(
                            errorMessage == nil ? Theme.stroke : Theme.danger.opacity(0.7),
                            lineWidth: 1
                        )
                }
        }
    }

    private var nameField: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                fieldLabel("Name")
                Spacer()
                Text("Optional · \(nameText.count)/40")
                    .ldFont(11, relativeTo: .caption2)
                    .foregroundStyle(Theme.muted2)
            }

            TextField("Suggested from the site", text: $nameText)
                .ldFont(15, relativeTo: .body)
                .foregroundStyle(Theme.text)
                .tint(Theme.accent)
                .textInputAutocapitalization(.words)
                .submitLabel(.done)
                .focused($focusedField, equals: .name)
                .accessibilityIdentifier("nameField")
                .onSubmit(add)
                .padding(.horizontal, 14)
                .frame(height: 52)
                .background(Theme.surface)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                .overlay {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .strokeBorder(Theme.stroke, lineWidth: 1)
                }
        }
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .ldFont(11, weight: .semibold, relativeTo: .caption2)
            .tracking(0.8)
            .foregroundStyle(Theme.muted2)
    }

    private var addButton: some View {
        Button(action: add) {
            Text("Add to deck")
                .ldFont(15, weight: .semibold, relativeTo: .body)
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
        .accessibilityIdentifier("addToDeckButton")
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
        .padding(.bottom, 8)
        .background(Theme.bg)
    }

    private func add() {
        do {
            let result = try URLNormalizer.normalize(urlText)
            let suggested = LinkItem.suggestedName(forHost: result.host)
            let name = LinkItem.sanitizedName(nameText, fallback: suggested)
            app.deck.add(name: name, url: result.url.absoluteString)
            focusedField = nil
            dismiss()
        } catch {
            errorMessage = error.message
            focusedField = .url
        }
    }
}
