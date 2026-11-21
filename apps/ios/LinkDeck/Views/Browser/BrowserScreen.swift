import SwiftUI
import WebKit

@MainActor
struct BrowserScreen: View {
    let link: LinkItem
    let app: AppModel

    @Environment(\.dismiss) private var dismiss
    @State private var controller: BrowserController
    @State private var showHomeSheet = false
    @State private var showRemoveConfirm = false

    init(link: LinkItem, app: AppModel) {
        self.link = link
        self.app = app
        _controller = State(initialValue: BrowserController(link: link, app: app))
    }

    var body: some View {
        ZStack(alignment: .top) {
            Theme.bg.ignoresSafeArea()

            BrowserWebView(controller: controller)
                .ignoresSafeArea(edges: .bottom)

            if let message = controller.loadError {
                errorCard(message)
            }

            headerLayer
        }
        .background(Theme.bg)
        .statusBarHidden(false)
        .onAppear {
            controller.onDismiss = { dismiss() }
        }
        .onDisappear {
            controller.tearDown()
        }
        .sheet(isPresented: $showHomeSheet) {
            HomeScreenSheet(
                siteName: controller.pageTitle.isEmpty ? link.name : controller.pageTitle,
                siteURL: controller.currentURL
            )
            .environment(app)
        }
        .confirmationDialog(
            "Remove \(link.name) from your deck?",
            isPresented: $showRemoveConfirm,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                controller.removeFromDeck()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This closes the page and removes the link. The site itself isn't changed.")
        }
        .alert(
            "Blocked domain",
            isPresented: Binding(
                get: { controller.blockedHostWarning != nil },
                set: { if !$0 { controller.blockedHostWarning = nil } }
            )
        ) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("\(controller.blockedHostWarning ?? "This host") is on LinkDeck's block list. It's loading anyway because you opened it deliberately.")
        }
    }

    private var headerLayer: some View {
        VStack(spacing: 0) {
            if controller.controlsVisible {
                BrowserHeader(
                    controller: controller,
                    onBack: {
                        if controller.canGoBack {
                            controller.goBack()
                        } else {
                            dismiss()
                        }
                    },
                    onHomeScreen: { showHomeSheet = true },
                    onRemove: { showRemoveConfirm = true }
                )
                .padding(.horizontal, 10)
                .padding(.top, 4)
                .transition(.opacity.combined(with: .offset(y: -10)))
            } else {
                Button {
                    controller.showControls()
                } label: {
                    Capsule()
                        .fill(Theme.muted.opacity(0.55))
                        .frame(width: 36, height: 4)
                        .frame(maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Show browser controls")
                .transition(.opacity)
            }

            Spacer()
        }
        .animation(.easeOut(duration: 0.18), value: controller.controlsVisible)
    }

    private func errorCard(_ message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 28, weight: .medium))
                .foregroundStyle(Theme.muted)

            Text("Couldn't load this page")
                .ldFont(18, weight: .semibold, relativeTo: .headline)
                .foregroundStyle(Theme.text)

            Text(message)
                .ldFont(13, relativeTo: .footnote)
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)

            Button {
                controller.reload()
            } label: {
                Text("Try again")
                    .ldFont(14, weight: .semibold, relativeTo: .subheadline)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 20)
                    .frame(height: 42)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(TileButtonStyle())
            .padding(.top, 2)
        }
        .padding(24)
        .frame(maxWidth: 320)
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
        .padding(28)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct BrowserHeader: View {
    let controller: BrowserController
    let onBack: () -> Void
    let onHomeScreen: () -> Void
    let onRemove: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("browserBack")
                .accessibilityLabel(controller.canGoBack ? "Back" : "Close")

                HStack(spacing: 5) {
                    Image(systemName: controller.isSecure ? "lock.fill" : "lock.open")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(controller.isSecure ? Theme.muted : Theme.muted2)
                    Text(controller.displayHost)
                        .ldFont(14, weight: .semibold, relativeTo: .subheadline)
                        .foregroundStyle(Theme.text)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(controller.isSecure ? "Secure" : "Not secure") \(controller.displayHost)")

                HStack(spacing: 4) {
                    Image(systemName: "shield.fill")
                        .font(.system(size: 10, weight: .semibold))
                    Text(Format.count(controller.sessionBlocked))
                        .ldFont(11, weight: .semibold, relativeTo: .caption2)
                }
                .foregroundStyle(controller.sessionBlocked > 0 ? Theme.success : Theme.muted)
                .padding(.horizontal, 8)
                .frame(height: 30)
                .background(Theme.surface2, in: Capsule())
                .accessibilityLabel("\(Format.count(controller.sessionBlocked)) blocked in this session")

                Menu {
                    Button {
                        controller.reload()
                    } label: {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }

                    Button {
                        controller.toggleDesktopSite()
                    } label: {
                        Label(
                            "Desktop site",
                            systemImage: controller.desktopMode ? "checkmark" : "desktopcomputer"
                        )
                    }

                    Divider()

                    Button {
                        controller.openInSafari()
                    } label: {
                        Label("Open in Safari", systemImage: "safari")
                    }

                    Button {
                        onHomeScreen()
                    } label: {
                        Label("Add to Home Screen", systemImage: "plus.rectangle.on.rectangle")
                    }

                    Divider()

                    Button(role: .destructive) {
                        onRemove()
                    } label: {
                        Label("Remove from deck", systemImage: "trash")
                    }
                } label: {
                    Image(systemName: "ellipsis")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.text)
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .accessibilityIdentifier("browserMenu")
                .accessibilityLabel("Browser menu")
            }
            .padding(.horizontal, 4)

            if controller.isLoading {
                GeometryReader { geometry in
                    ZStack(alignment: .leading) {
                        Rectangle()
                            .fill(Theme.stroke.opacity(0.5))
                        Rectangle()
                            .fill(Theme.accent)
                            .frame(width: max(0, geometry.size.width * controller.progress))
                            .animation(.easeOut(duration: 0.2), value: controller.progress)
                    }
                }
                .frame(height: 2)
                .clipped()
            }
        }
        .background(Theme.surface.opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .strokeBorder(Theme.stroke, lineWidth: 1)
        }
    }
}

private struct BrowserWebView: UIViewRepresentable {
    let controller: BrowserController

    func makeUIView(context: Context) -> WKWebView {
        controller.webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}
}
