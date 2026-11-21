import SwiftUI
import WebKit

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: DeckStore
    let blocklist: BlocklistService
    @Environment(\.dismiss) private var dismiss

    @State private var confirmClearWeb = false
    @State private var confirmRemoveAll = false
    @State private var clearing = false

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("Settings")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Spacer()
                IconButton(systemName: "xmark", label: "Close settings", action: { dismiss() })
            }
            .padding(.bottom, 18)

            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    section("Blocking") {
                        VStack(spacing: 0) {
                            toggleRow(
                                title: "Block ads and trackers",
                                subtitle: "Suffix-matched host blocking plus cosmetic filters. Reloads open pages.",
                                isOn: $settings.blockAds
                            )
                            divider
                            toggleRow(
                                title: "Block popups",
                                subtitle: "Suppresses windows that were not opened by a real click.",
                                isOn: $settings.blockPopups
                            )
                        }
                        .background(card)
                    }

                    section("Data") {
                        VStack(spacing: 0) {
                            actionRow(
                                title: "Clear browsing data",
                                subtitle: clearing ? "Clearing…" : "Cookies, caches, local storage, cached favicons, and blocked counters.",
                                destructive: false,
                                disabled: clearing
                            ) {
                                confirmClearWeb = true
                            }
                            divider
                            actionRow(
                                title: "Remove all links",
                                subtitle: store.links.isEmpty ? "The deck is already empty." : "Removes \(Format.links(store.links.count)) from the deck.",
                                destructive: true,
                                disabled: store.links.isEmpty
                            ) {
                                confirmRemoveAll = true
                            }
                        }
                        .background(card)
                    }

                    section("About") {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Text("Version")
                                    .font(.system(size: 14, weight: .medium))
                                    .foregroundStyle(Theme.text)
                                Spacer()
                                Text(version)
                                    .font(.system(size: 13))
                                    .foregroundStyle(Theme.muted)
                            }

                            Text(
                                "LinkDeck compiles \(Format.count(blocklist.domainCount)) known ad and tracker domains into Apple's content-blocking engine, so matching requests never reach the page. Cosmetic filters hide leftover ad slots and popup guards stop script-driven windows.\n\nWebKit does not report how many network requests a rule list stops. The blocked count on a tile therefore reflects cosmetic and popup filtering, not every blocked network request."
                            )
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.muted)
                            .fixedSize(horizontal: false, vertical: true)

                            Text("Links, settings, and counts stay on this Mac. The only network requests LinkDeck makes itself are favicon requests to DuckDuckGo; pages load normally, minus blocked hosts.")
                                .font(.system(size: 12))
                                .foregroundStyle(Theme.muted2)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(14)
                        .background(card)
                    }
                }
                .padding(.bottom, 4)
            }
            .scrollIndicators(.visible)
        }
        .padding(24)
        .frame(width: 520, height: 600)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
        .onExitCommand { dismiss() }
        .alert("Clear browsing data?", isPresented: $confirmClearWeb) {
            Button("Cancel", role: .cancel) {}
            Button("Clear", role: .destructive) { clearBrowsingData() }
        } message: {
            Text("Removes cookies, caches, local storage, and cached favicons for every site, and resets blocked counts. Your links stay on the deck.")
        }
        .alert("Remove all links?", isPresented: $confirmRemoveAll) {
            Button("Cancel", role: .cancel) {}
            Button("Remove all", role: .destructive) { store.removeAll() }
        } message: {
            Text("This clears the deck. Generated apps in ~/Applications/LinkDeck are not deleted.")
        }
    }

    private var card: some View {
        RoundedRectangle(cornerRadius: 16, style: .continuous)
            .fill(Theme.surface)
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(Theme.stroke, lineWidth: 1)
            )
    }

    private var divider: some View {
        Rectangle()
            .fill(Theme.stroke)
            .frame(height: 1)
            .padding(.leading, 14)
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.system(size: 12, weight: .semibold))
                .tracking(1.2)
                .foregroundStyle(Theme.muted2)
            content()
        }
    }

    private func toggleRow(title: String, subtitle: String, isOn: Binding<Bool>, disabled: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(Theme.text)
                Text(subtitle)
                    .font(.system(size: 12))
                    .foregroundStyle(Theme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            Toggle("", isOn: isOn)
                .labelsHidden()
                .toggleStyle(.switch)
                .tint(Theme.accent)
                .accessibilityLabel(title)
                .disabled(disabled)
                .opacity(disabled ? 0.45 : 1)
        }
        .padding(14)
    }

    private func actionRow(title: String, subtitle: String, destructive: Bool, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(destructive ? Theme.danger : Theme.text)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.muted)
                }
                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .opacity(disabled ? 0.45 : 1)
    }

    private func clearBrowsingData() {
        clearing = true
        let types = WKWebsiteDataStore.allWebsiteDataTypes()
        WKWebsiteDataStore.default().removeData(ofTypes: types, modifiedSince: .distantPast) {
            DispatchQueue.main.async {
                FaviconService.shared.clearCache()
                store.resetBlockedCounts()
                clearing = false
            }
        }
    }
}
