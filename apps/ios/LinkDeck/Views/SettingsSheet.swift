import SwiftUI
import WebKit

struct SettingsSheet: View {
    @Environment(AppModel.self) private var app
    @Environment(\.dismiss) private var dismiss

    @State private var showClearConfirm = false
    @State private var showRemoveAllConfirm = false
    @State private var showHomeTip = false
    @State private var statusMessage: String?

    var body: some View {
        @Bindable var app = app

        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                header

                section("Blocking") {
                    VStack(spacing: 0) {
                        Toggle(isOn: $app.blockAds) {
                            toggleLabel(
                                "Block ads & trackers",
                                detail: "Suffix-matches \(Format.count(app.blocker.domainCount)) known ad domains before they load."
                            )
                        }
                        .tint(Theme.accent)
                        .accessibilityIdentifier("blockAdsToggle")
                        .padding(16)

                        divider

                        Toggle(isOn: $app.blockPopups) {
                            toggleLabel(
                                "Block popups",
                                detail: "Stops script-driven windows that weren't opened by a tap."
                            )
                        }
                        .tint(Theme.accent)
                        .accessibilityIdentifier("blockPopupsToggle")
                        .padding(16)
                    }
                    .ldSurfaceCard()
                }

                section("Data") {
                    VStack(spacing: 0) {
                        actionRow(
                            title: "Clear browsing data",
                            detail: "Cookies, caches, favicons and blocked counts.",
                            icon: "trash"
                        ) {
                            showClearConfirm = true
                        }

                        divider

                        actionRow(
                            title: "Remove all links",
                            detail: "Clears the deck completely.",
                            icon: "rectangle.stack.badge.minus",
                            destructive: true
                        ) {
                            showRemoveAllConfirm = true
                        }
                    }
                    .ldSurfaceCard()
                }

                if let statusMessage {
                    Label(statusMessage, systemImage: "checkmark.circle.fill")
                        .ldFont(13, relativeTo: .footnote)
                        .foregroundStyle(Theme.success)
                        .transition(.opacity)
                }

                section("About") {
                    VStack(alignment: .leading, spacing: 0) {
                        HStack {
                            Text("Version")
                                .ldFont(15, relativeTo: .body)
                                .foregroundStyle(Theme.text)
                            Spacer()
                            Text(version)
                                .ldFont(14, relativeTo: .subheadline)
                                .foregroundStyle(Theme.muted)
                        }
                        .padding(16)

                        divider

                        VStack(alignment: .leading, spacing: 8) {
                            Text("How it works")
                                .ldFont(14, weight: .semibold, relativeTo: .subheadline)
                                .foregroundStyle(Theme.text)
                            Text("Saved links open full-screen in a chrome-free web view. LinkDeck blocks requests to known ad and tracker domains, hides leftover ad slots, and keeps everything on your device. No account, no sync, no analytics.")
                                .ldFont(13, relativeTo: .footnote)
                                .foregroundStyle(Theme.muted)
                                .lineSpacing(3)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(16)

                        divider

                        Button {
                            showHomeTip = true
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: "plus.rectangle.on.rectangle")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Theme.accent)
                                    .frame(width: 30, height: 30)
                                    .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
                                Text("Install LinkDeck on your Home Screen")
                                    .ldFont(14, weight: .medium, relativeTo: .subheadline)
                                    .foregroundStyle(Theme.text)
                                    .multilineTextAlignment(.leading)
                                Spacer(minLength: 4)
                                Image(systemName: "chevron.right")
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(Theme.muted2)
                            }
                            .padding(16)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .ldSurfaceCard()
                }

                pinningNote
            }
            .padding(.horizontal, Theme.screenPadding)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollIndicators(.hidden)
        .background(Theme.bg.ignoresSafeArea())
        .presentationDetents([.large])
        .presentationDragIndicator(.hidden)
        .presentationBackground(Theme.bg)
        .sheet(isPresented: $showHomeTip) {
            HomeScreenSheet(siteName: nil, siteURL: nil)
                .environment(app)
        }
        .alert("Clear browsing data?", isPresented: $showClearConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive, action: clearBrowsingData)
        } message: {
            Text("Cookies, caches, favicons and every saved blocked count will be removed. Your links stay on the deck.")
        }
        .alert("Remove all links?", isPresented: $showRemoveAllConfirm) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) {
                app.deck.removeAll()
                app.deck.flush()
                showStatus("Deck cleared.")
            }
        } message: {
            Text("Every saved link will be removed from your deck. This can't be undone.")
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Settings")
                    .ldFont(28, weight: .semibold, relativeTo: .title)
                    .foregroundStyle(Theme.text)
                Text("Everything stays on this device.")
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
            .accessibilityIdentifier("closeSettings")
            .accessibilityLabel("Close")
        }
        .padding(.top, 12)
    }

    private var pinningNote: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(Theme.muted)
            VStack(alignment: .leading, spacing: 4) {
                Text("Home Screen pinning on iOS")
                    .ldFont(13, weight: .semibold, relativeTo: .footnote)
                    .foregroundStyle(Theme.text)
                Text("iOS doesn't let an app create Home Screen web clips for other sites. LinkDeck is the launcher; add a site from Safari's Share menu if you want its own icon.")
                    .ldFont(12, relativeTo: .caption)
                    .foregroundStyle(Theme.muted)
                    .lineSpacing(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(14)
        .background(Theme.surface2.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func section<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .ldFont(11, weight: .semibold, relativeTo: .caption2)
                .tracking(0.9)
                .foregroundStyle(Theme.muted2)
                .padding(.leading, 2)
            content()
        }
    }

    private func toggleLabel(_ title: String, detail: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .ldFont(15, weight: .medium, relativeTo: .body)
                .foregroundStyle(Theme.text)
            Text(detail)
                .ldFont(12, relativeTo: .caption)
                .foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.trailing, 8)
    }

    private func actionRow(
        title: String,
        detail: String,
        icon: String,
        destructive: Bool = false,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(destructive ? Theme.danger : Theme.muted)
                    .frame(width: 30, height: 30)
                    .background(
                        (destructive ? Theme.danger : Theme.muted).opacity(0.1),
                        in: RoundedRectangle(cornerRadius: 8, style: .continuous)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .ldFont(15, relativeTo: .body)
                        .foregroundStyle(destructive ? Theme.danger : Theme.text)
                    Text(detail)
                        .ldFont(12, relativeTo: .caption)
                        .foregroundStyle(Theme.muted)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.muted2)
            }
            .padding(16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityHint(detail)
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
            .padding(.leading, 16)
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private func clearBrowsingData() {
        WKWebsiteDataStore.default().removeData(
            ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(),
            modifiedSince: .distantPast
        ) {
            Task { @MainActor in
                URLCache.shared.removeAllCachedResponses()
                FaviconLoader.shared.clear()
                app.deck.resetBlockedCounts()
                app.deck.flush()
                showStatus("Browsing data cleared.")
            }
        }
    }

    private func showStatus(_ text: String) {
        withAnimation(.easeOut(duration: 0.18)) {
            statusMessage = text
        }
        Task {
            try? await Task.sleep(for: .seconds(2.5))
            withAnimation(.easeOut(duration: 0.18)) {
                if statusMessage == text { statusMessage = nil }
            }
        }
    }
}
