import Combine
import Foundation

@MainActor
final class DeckUIModel: ObservableObject {
    @Published var showAddLink = false
    @Published var showSettings = false
}

@MainActor
final class BrowserUIModel: ObservableObject {
    @Published var showSettings = false
}
