import SwiftUI
import WebKit

struct WebAppView: View {
    @ObservedObject var model: BrowserModel
    @ObservedObject var settings: AppSettings
    @ObservedObject var store: DeckStore
    @ObservedObject var ui: BrowserUIModel
    let blocklist: BlocklistService

    var body: some View {
        ZStack(alignment: .top) {
            Color.black

            WebViewHost(webView: model.webView)

            if let message = model.errorMessage {
                errorCard(message)
            }

            if model.headerVisible {
                BrowserHeader(model: model)
                    .padding(.horizontal, 12)
                    .padding(.top, 34)
                    .transition(.move(edge: .top).combined(with: .opacity))
            } else {
                hotspot
            }
        }
        .ignoresSafeArea()
        .animation(.easeOut(duration: 0.16), value: model.headerVisible)
        .sheet(isPresented: $ui.showSettings) {
            SettingsView(settings: settings, store: store, blocklist: blocklist)
        }
        .onAppear {
            model.revealHeader()
        }
    }

    private var hotspot: some View {
        HStack {
            Spacer()
            Button {
                model.revealHeader()
            } label: {
                Capsule()
                    .fill(Theme.muted2.opacity(0.65))
                    .frame(width: 64, height: 3)
                    .padding(.top, 3)
                    .frame(width: 120, height: 14, alignment: .top)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Show toolbar")
            .help("Show toolbar")
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .frame(height: 14)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .regular))
                .foregroundStyle(Theme.muted)
            Text("This page couldn’t load")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            Button("Reload") { model.reload() }
                .buttonStyle(SecondaryButtonStyle())
                .padding(.top, 4)
        }
        .padding(22)
        .frame(maxWidth: 360)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

private struct WebViewHost: NSViewRepresentable {
    let webView: WKWebView

    func makeNSView(context: Context) -> WKWebView {
        webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}
}

struct BrowserHeader: View {
    @ObservedObject var model: BrowserModel

    var body: some View {
        HStack(spacing: 4) {
            Button {
                model.goBackOrClose()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(model.canGoBack ? "Back" : "Close")
            .help(model.canGoBack ? "Back (⌘[)" : "Close")

            HStack(spacing: 5) {
                Image(systemName: model.isSecure ? "lock.fill" : "lock.open")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.isSecure ? Theme.muted : Theme.muted2)
                Text(model.host)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .layoutPriority(1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("\(model.isSecure ? "Secure" : "Not secure"): \(model.host)")

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "shield.fill")
                    .font(.system(size: 11, weight: .semibold))
                Text(Format.count(model.blockedSession))
                    .font(.system(size: 12, weight: .medium))
                    .contentTransition(.numericText())
            }
            .foregroundStyle(model.blockedSession > 0 ? Theme.success : Theme.muted)
            .padding(.horizontal, 9)
            .frame(height: 26)
            .background(
                Capsule().fill(
                    model.blockedSession > 0 ? Theme.success.opacity(0.11) : Theme.surface2
                )
            )
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(Format.count(model.blockedSession)) blocked this session")

            menu
        }
        .padding(.leading, 6)
        .padding(.trailing, 6)
        .frame(height: 52)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Theme.surface.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Theme.stroke, lineWidth: 1)
        )
        .overlay(alignment: .bottom) {
            if model.isLoading {
                ProgressLine(progress: model.progress)
                    .padding(.horizontal, 14)
                    .padding(.bottom, 5)
            }
        }
        .onHover { model.headerHoverChanged($0) }
    }

    private var menu: some View {
        Menu {
            Button("Reload") { model.reload() }
            Toggle("Desktop site", isOn: Binding(
                get: { model.desktopMode },
                set: { _ in model.toggleDesktopSite() }
            ))
            Button("Open in Safari") { model.openInSafari() }
            Divider()
            Button("Pin as app") { model.pinCurrentSite() }
            Button("Remove from deck", role: .destructive) { model.removeFromDeck() }
        } label: {
            Image(systemName: "ellipsis")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Theme.text)
                .frame(width: 44, height: 44)
                .contentShape(Rectangle())
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .accessibilityLabel("Site menu")
        .help("Site menu")
    }
}

private struct ProgressLine: View {
    let progress: Double

    var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .leading) {
                Capsule().fill(Theme.accent.opacity(0.16))
                Capsule()
                    .fill(Theme.accent)
                    .frame(width: max(2, geometry.size.width * min(max(progress, 0), 1)))
            }
        }
        .frame(height: 2)
    }
}
