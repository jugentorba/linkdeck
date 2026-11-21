import SwiftUI

struct DeckView: View {
    @Environment(AppModel.self) private var app
    @Environment(\.scenePhase) private var scenePhase

    @State private var activeSheet: DeckSheet?
    @State private var selectedLink: LinkItem?
    @State private var renameTarget: LinkItem?
    @State private var renameDraft = ""
    @State private var removeTarget: LinkItem?
    @State private var didHandleLaunchEnvironment = false

    private let columns = [
        GridItem(.adaptive(minimum: 150), spacing: Theme.gridGap)
    ]

    var body: some View {
        VStack(spacing: 0) {
            header

            if app.deck.links.isEmpty {
                EmptyDeckView { activeSheet = .add }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.opacity)
            } else {
                ScrollView {
                    LazyVGrid(columns: columns, spacing: Theme.gridGap) {
                        ForEach(Array(app.deck.links.enumerated()), id: \.element.id) { index, link in
                            Button {
                                selectedLink = link
                            } label: {
                                LinkTileView(link: link, index: index)
                            }
                                .buttonStyle(TileButtonStyle())
                                .accessibilityIdentifier("deckTile")
                                .contextMenu {
                                    Button {
                                        selectedLink = link
                                    } label: {
                                        Label("Open", systemImage: "arrow.up.right.square")
                                    }

                                    Button {
                                        activeSheet = .home(link)
                                    } label: {
                                        Label("Add to Home Screen", systemImage: "plus.rectangle.on.rectangle")
                                    }

                                    Button {
                                        renameDraft = link.name
                                        renameTarget = link
                                    } label: {
                                        Label("Rename", systemImage: "pencil")
                                    }

                                    Divider()

                                    Button(role: .destructive) {
                                        removeTarget = link
                                    } label: {
                                        Label("Remove", systemImage: "trash")
                                    }
                                }
                        }
                    }
                    .padding(.horizontal, Theme.screenPadding)
                    .padding(.top, 20)
                    .padding(.bottom, 44)
                }
                .scrollIndicators(.hidden)
            }
        }
        .background(Theme.bg.ignoresSafeArea())
        .task {
            await app.prepare()
            openEnvironmentLinkIfRequested()
        }
        .onOpenURL { url in
            openDeepLink(url)
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .background { app.deck.flush() }
        }
        .fullScreenCover(item: $selectedLink) { link in
            BrowserScreen(link: link, app: app)
        }
        .sheet(item: $activeSheet) { sheet in
            switch sheet {
            case .add:
                AddLinkSheet()
                    .environment(app)
            case .settings:
                SettingsSheet()
                    .environment(app)
            case .home(let link):
                HomeScreenSheet(siteName: link.name, siteURL: link.webURL)
                    .environment(app)
            }
        }
        .alert("Rename link", isPresented: renameBinding) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) { renameTarget = nil }
            Button("Save") {
                if let target = renameTarget {
                    app.deck.rename(id: target.id, name: renameDraft)
                }
                renameTarget = nil
            }
        } message: {
            Text("Give this link a name you'll recognize.")
        }
        .confirmationDialog(
            removeTarget.map { "Remove \($0.name)?" } ?? "Remove link?",
            isPresented: removeBinding,
            titleVisibility: .visible
        ) {
            Button("Remove", role: .destructive) {
                if let target = removeTarget {
                    app.deck.remove(id: target.id)
                    app.deck.flush()
                }
                removeTarget = nil
            }
            Button("Cancel", role: .cancel) { removeTarget = nil }
        } message: {
            Text("This only removes it from your deck. The site itself isn't changed.")
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LinkDeck")
                    .ldFont(32, weight: .semibold, relativeTo: .largeTitle)
                    .foregroundStyle(Theme.text)
                    .lineLimit(1)

                Text(subtitle)
                    .ldFont(13, relativeTo: .footnote)
                    .foregroundStyle(Theme.muted)
                    .lineLimit(1)
                    .accessibilityLabel("\(app.deck.links.count) saved links, \(app.deck.totalBlocked) blocked requests")
            }

            Spacer(minLength: 8)

            Button {
                activeSheet = .add
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(Theme.bg)
                    .frame(width: 44, height: 44)
                    .background(Theme.accent, in: Circle())
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityIdentifier("addLinkButton")
            .accessibilityLabel("Add a link")

            Button {
                activeSheet = .settings
            } label: {
                Image(systemName: "gearshape")
                    .font(.system(size: 18, weight: .medium))
                    .foregroundStyle(Theme.text)
                    .frame(width: 44, height: 44)
                    .background(Theme.surface2, in: Circle())
                    .overlay {
                        Circle().strokeBorder(Theme.stroke, lineWidth: 1)
                    }
            }
            .buttonStyle(TileButtonStyle())
            .accessibilityIdentifier("settingsButton")
            .accessibilityLabel("Settings")
        }
        .padding(.horizontal, Theme.screenPadding)
        .padding(.top, 12)
    }

    private var subtitle: String {
        let count = app.deck.links.count
        let linkWord = count == 1 ? "link" : "links"
        return "\(count) \(linkWord) · \(Format.count(app.deck.totalBlocked)) blocked"
    }

    private var renameBinding: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }

    private var removeBinding: Binding<Bool> {
        Binding(
            get: { removeTarget != nil },
            set: { if !$0 { removeTarget = nil } }
        )
    }

    private func openDeepLink(_ url: URL) {
        guard url.scheme?.lowercased() == "linkdeck",
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let raw = components.queryItems?.first(where: { $0.name == "url" })?.value,
              let normalized = try? URLNormalizer.normalize(raw) else { return }
        let requestedName = components.queryItems?.first(where: { $0.name == "name" })?.value ?? ""
        let link = app.deck.add(name: requestedName, url: normalized.url.absoluteString)
        selectedLink = link
    }

    /// Developer/automation hook: open a transient site on launch without touching
    /// the deck. Used by `run.sh --open <url>` and simulator tests.
    private func openEnvironmentLinkIfRequested() {
        guard !didHandleLaunchEnvironment else { return }
        didHandleLaunchEnvironment = true
        let environment = ProcessInfo.processInfo.environment
        guard let raw = environment["LINKDECK_OPEN_URL"],
              let normalized = try? URLNormalizer.normalize(raw) else { return }
        let requestedName = environment["LINKDECK_OPEN_NAME"] ?? ""
        let name = requestedName.isEmpty
            ? LinkItem.suggestedName(forURLString: normalized.url.absoluteString)
            : requestedName
        selectedLink = LinkItem(name: name, url: normalized.url.absoluteString)
    }
}

private enum DeckSheet: Identifiable {
    case add
    case settings
    case home(LinkItem)

    var id: String {
        switch self {
        case .add: return "add"
        case .settings: return "settings"
        case .home(let link): return "home-\(link.id.uuidString)"
        }
    }
}

private struct EmptyDeckView: View {
    let onAdd: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            ZStack {
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Theme.surface)
                    .frame(width: 88, height: 88)
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(Theme.stroke, lineWidth: 1)
                    }
                Image(systemName: "link")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.accent)
            }
            .accessibilityHidden(true)

            VStack(spacing: 8) {
                Text("Nothing here yet")
                    .ldFont(24, weight: .semibold, relativeTo: .title2)
                    .foregroundStyle(Theme.text)

                Text("Paste a link and it becomes an app on your deck — no browser chrome, no ads.")
                    .ldFont(15, relativeTo: .body)
                    .foregroundStyle(Theme.muted)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 310)
            }

            Button(action: onAdd) {
                Text("Add a link")
                    .ldFont(15, weight: .semibold, relativeTo: .body)
                    .foregroundStyle(Theme.bg)
                    .padding(.horizontal, 22)
                    .frame(height: 48)
                    .background(Theme.accent, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(TileButtonStyle())
            .padding(.top, 2)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 40)
        .accessibilityElement(children: .contain)
    }
}

struct TileButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .opacity(configuration.isPressed ? 0.72 : 1)
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
