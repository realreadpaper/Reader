import SwiftUI
import SwiftData

extension Notification.Name {
    static let readerOpenFiles = Notification.Name("ReaderOpenFiles")
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        let urls = filenames.map { URL(fileURLWithPath: $0) }
        NotificationCenter.default.post(
            name: .readerOpenFiles,
            object: self,
            userInfo: ["urls": urls]
        )
        sender.reply(toOpenOrPrint: .success)
    }
}

@main
struct ReaderApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var themeManager = ThemeManager()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(themeManager)
        }
        .modelContainer(for: [Book.self, Bookmark.self, Highlight.self])
    }
}
