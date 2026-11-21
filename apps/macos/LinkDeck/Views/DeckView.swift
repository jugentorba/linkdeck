import AppKit
import SwiftUI

struct DeckView: View {
    @ObservedObject var store: DeckStore
    @ObservedObject var settings: AppSettings
    @ObservedObject var ui: DeckUIModel
    let blocklist: BlocklistService
    let onOpen: (DeckLink) -> Void
    let onPin: (DeckLink) -> Void

    @State private var renameTarget: DeckLink?
    @State private var renameDraft = ""
    @State private var showRename = false

    private let columns = [
        GridItem(.adaptive(minimum: 150, maximum: .infinity), spacing: Theme.gap, alignment: .top)
    ]

    var body: some View {
        ZStack {
            Theme.bg.ignoresSafeArea()

            VStack(alignment: .leading, spacing: 0) {
                header

                if store.links.isEmpty {
                    emptyState
                } else {
                    ScrollView {
                        LazyVGrid(columns: columns, alignment: .leading, spacing: Theme.gap) {
                            ForEach(Array(store.links.enumerated()), id: \.element.id) { index, link in
                                DeckTile(
                                    link: link,
                                    index: index,
                                    onOpen: { onOpen(link) },
                                    onPin: { onPin(link) },
                                    onRename: {
                                        renameTarget = link
                                        renameDraft = link.name
                                        showRename = true
                                    },
                                    onRemove: {
                                        withAnimation(.easeOut(duration: 0.15)) {
                                            store.remove(id: link.id)
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal, Theme.margin)
                        .padding(.top, 6)
                        .padding(.bottom, 32)
                    }
                }
            }
            .ignoresSafeArea()
        }
        .sheet(isPresented: $ui.showAddLink) {
            AddLinkView(store: store)
        }
        .sheet(isPresented: $ui.showSettings) {
            SettingsView(settings: settings, store: store, blocklist: blocklist)
        }
        .alert("Rename link", isPresented: $showRename) {
            TextField("Name", text: $renameDraft)
            Button("Cancel", role: .cancel) {}
            Button("Save") {
                if let target = renameTarget {
                    store.rename(id: target.id, to: renameDraft)
                }
            }
        } message: {
            Text("Names are limited to \(LinkInput.maxNameLength) characters.")
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text("LinkDeck")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(Theme.text)
                Text(Format.deckSubtitle(links: store.links.count, blocked: store.totalBlocked))
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.muted)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 12)

            IconButton(systemName: "plus", label: "Add a link", help: "Add a link (⌘N)") {
                ui.showAddLink = true
            }
            IconButton(systemName: "gearshape.fill", label: "Settings", help: "Settings (⌘,)") {
                ui.showSettings = true
            }
        }
        .padding(.horizontal, Theme.margin)
        .padding(.top, 38)
        .padding(.bottom, 22)
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: 42, weight: .light))
                .foregroundStyle(Theme.muted2)
                .padding(.bottom, 4)

            Text("Nothing here yet")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(Theme.text)

            Text("Paste a link and it becomes an app on your deck — no browser chrome, no ads.")
                .font(.system(size: 15))
                .foregroundStyle(Theme.muted)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
                .frame(maxWidth: 380)

            Button {
                ui.showAddLink = true
            } label: {
                Label("Add a link", systemImage: "plus")
                    .labelStyle(.titleAndIcon)
            }
            .buttonStyle(PrimaryButtonStyle())
            .padding(.top, 8)
            .accessibilityLabel("Add a link")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 32)
        .padding(.bottom, 40)
    }
}
