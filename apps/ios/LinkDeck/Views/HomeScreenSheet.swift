import SwiftUI
import UIKit

/// Honest iOS Home Screen explanation. Pass a site to offer Safari + Copy link;
/// pass nil for the "Install LinkDeck itself" tip in Settings.
struct HomeScreenSheet: View {
    let siteName: String?
    let siteURL: URL?

    @Environment(\.dismiss) private var dismiss
    @State private var copied = false

    private var isSite: Bool { siteName != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    hero

                    Text(bodyCopy)
                        .ldFont(14, relativeTo: .subheadline)
                        .foregroundStyle(Theme.muted)
                        .lineSpacing(3)
                        .fixedSize(horizontal: false, vertical: true)

                    if isSite {
                        steps
                        note
                        buttons
                    } else {
                        appTip
                        doneButton
                    }
                }
                .padding(.horizontal, Theme.screenPadding)
                .padding(.top, 8)
                .padding(.bottom, 32)
            }
            .scrollIndicators(.hidden)
            .background(Theme.bg.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        dismiss()
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(Theme.muted)
                            .frame(width: 44, height: 44)
                    }
                    .accessibilityIdentifier("closeHomeSheet")
                    .accessibilityLabel("Close")
                }
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(Theme.bg)
    }

    private var hero: some View {
        HStack(spacing: 14) {
            if let siteName, let siteURL {
                FaviconView(
                    host: siteURL.host ?? "",
                    name: siteName,
                    size: 56,
                    cornerRadius: 16
                )
            } else {
                ZStack {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .fill(Theme.accent.opacity(0.16))
                    Image(systemName: "link")
                        .font(.system(size: 24, weight: .semibold))
                        .foregroundStyle(Theme.accent)
                }
                .frame(width: 56, height: 56)
                .overlay {
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(Theme.accent.opacity(0.3), lineWidth: 1)
                }
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .ldFont(22, weight: .semibold, relativeTo: .title2)
                    .foregroundStyle(Theme.text)
                    .fixedSize(horizontal: false, vertical: true)
                if let siteName {
                    Text(siteName)
                        .ldFont(13, relativeTo: .footnote)
                        .foregroundStyle(Theme.muted)
                        .lineLimit(1)
                }
            }
        }
        .padding(.top, 10)
    }

    private var title: String {
        isSite ? "Add to Home Screen" : "Install LinkDeck on your Home Screen"
    }

    private var bodyCopy: String {
        if isSite {
            return "LinkDeck is your launcher. iOS doesn't let an app pin another website to your Home Screen, so the closest thing is a Safari web clip — made in two steps."
        }
        return "LinkDeck is a native app, so iOS installs it from the App Store and apps can't add themselves to your Home Screen. If the icon isn't there yet, put it there from the App Library."
    }

    private var steps: some View {
        VStack(spacing: 0) {
            step(number: 1, text: "Open this site in Safari, then tap Share in the toolbar.")
            Rectangle().fill(Theme.stroke).frame(height: 1).padding(.leading, 50)
            step(number: 2, text: "Choose Add to Home Screen, then tap Add.")
        }
        .ldSurfaceCard()
    }

    private var note: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.muted)
            Text("The web clip opens in Safari with Safari's chrome. It won't have LinkDeck's full-screen view or ad blocking — this is an iOS limitation, not a LinkDeck setting.")
                .ldFont(12, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(13)
        .background(Theme.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button {
                guard let siteURL else { return }
                UIApplication.shared.open(siteURL)
            } label: {
                Label("Open in Safari", systemImage: "safari")
                    .ldFont(15, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(Theme.bg)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(TileButtonStyle())
            .disabled(siteURL == nil)
            .opacity(siteURL == nil ? 0.5 : 1)

            Button {
                guard let siteURL else { return }
                UIPasteboard.general.string = siteURL.absoluteString
                withAnimation(.easeOut(duration: 0.15)) { copied = true }
                Task {
                    try? await Task.sleep(for: .seconds(1.8))
                    withAnimation(.easeOut(duration: 0.15)) { copied = false }
                }
            } label: {
                Label(copied ? "Copied" : "Copy link", systemImage: copied ? "checkmark" : "doc.on.doc")
                    .ldFont(15, weight: .medium, relativeTo: .body)
                    .foregroundStyle(Theme.text)
                    .frame(maxWidth: .infinity)
                    .frame(height: 50)
                    .background(Theme.surface2, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    }
            }
            .buttonStyle(TileButtonStyle())
            .disabled(siteURL == nil)
            .opacity(siteURL == nil ? 0.5 : 1)
        }
        .padding(.top, 2)
    }

    private var appTip: some View {
        VStack(alignment: .leading, spacing: 10) {
            tipLine("1", "Open the App Library and find LinkDeck.")
            tipLine("2", "Touch and hold the app icon.")
            tipLine("3", "Choose Add to Home Screen.")
        }
        .padding(16)
        .ldSurfaceCard()
    }

    private func tipLine(_ number: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(number)
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.bg)
                .frame(width: 20, height: 20)
                .background(Theme.accent, in: Circle())
            Text(text)
                .ldFont(14, relativeTo: .subheadline)
                .foregroundStyle(Theme.text)
        }
    }

    private var doneButton: some View {
        Button {
            dismiss()
        } label: {
            Text("Done")
                .ldFont(15, weight: .semibold, relativeTo: .body)
                .foregroundStyle(Theme.bg)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        }
        .buttonStyle(TileButtonStyle())
    }

    private func step(number: Int, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Text("\(number)")
                .font(.system(size: 12, weight: .bold, design: .rounded))
                .foregroundStyle(Theme.bg)
                .frame(width: 24, height: 24)
                .background(Theme.accent, in: Circle())
            Text(text)
                .ldFont(14, relativeTo: .subheadline)
                .foregroundStyle(Theme.text)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(16)
    }
}
