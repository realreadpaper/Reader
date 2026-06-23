import SwiftUI
import SwiftData

@main
struct ReaderApp: App {
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(themeManager)
        }
        .modelContainer(for: [Book.self, Bookmark.self, Highlight.self])
    }
}
