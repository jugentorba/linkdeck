import SwiftUI

@main
struct LinkDeckApp: App {
    @State private var app = AppModel()

    var body: some Scene {
        WindowGroup {
            DeckView()
                .environment(app)
                .preferredColorScheme(.dark)
                .tint(Theme.accent)
        }
    }
}
