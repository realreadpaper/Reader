import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var themeManager = ThemeManager()
    @State private var selectedBook: Book?
    @State private var showSidebar = true
    @State private var storageService: StorageService?

    var body: some View {
        HSplitView {
            if showSidebar, let storageService {
                SidebarView(
                    selectedBook: $selectedBook,
                    storageService: storageService
                )
                .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
            }

            if let book = selectedBook, let storageService {
                ReaderView(book: book, themeManager: themeManager, storageService: storageService)
            } else {
                WelcomeView(themeManager: themeManager)
            }
        }
        .environment(themeManager)
        .frame(minWidth: 800, minHeight: 600)
        .task {
            if storageService == nil {
                storageService = StorageService(modelContext: modelContext)
            }
        }
        .onAppear {
            NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "s" {
                    showSidebar.toggle()
                    return nil
                }
                return event
            }
        }
    }
}

struct WelcomeView: View {
    let themeManager: ThemeManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book")
                .font(.system(size: 64))
                .foregroundStyle(themeManager.currentTheme.accent)
            Text("选择一本书开始阅读")
                .font(.title2)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.contentBG)
    }
}
