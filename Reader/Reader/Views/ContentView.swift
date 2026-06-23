import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let supportedImportTypes: [UTType] = {
    var types: [UTType] = []
    if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
    if let mobi = UTType(filenameExtension: "mobi") { types.append(mobi) }
    if let pdf = UTType(filenameExtension: "pdf") { types.append(pdf) }
    return types
}()

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedBook: Book?
    @State private var showSidebar = true
    @State private var storageService: StorageService?
    @State private var library: BookLibrary?
    @State private var importError: String?
    @State private var showImportPicker = false

    var body: some View {
        Group {
            if let storageService, let library {
                HSplitView {
                    if showSidebar {
                        SidebarView(
                            storageService: storageService,
                            library: library,
                            selectedBook: $selectedBook,
                            onRequestImport: { showImportPicker = true },
                            importError: $importError
                        )
                        .frame(minWidth: 200, idealWidth: 220, maxWidth: 280)
                    }

                    if let book = selectedBook {
                        ReaderView(
                            book: book,
                            storageService: storageService,
                            library: library
                        )
                    } else {
                        WelcomeView()
                    }
                }
            } else {
                LoadingView()
            }
        }
        .frame(minWidth: 800, minHeight: 600)
        .task {
            if storageService == nil {
                let service = StorageService(modelContext: modelContext)
                storageService = service
                library = BookLibrary(storageService: service)
            }
        }
        .fileImporter(
            isPresented: $showImportPicker,
            allowedContentTypes: supportedImportTypes
        ) { result in
            handleImportResult(result)
        }
        .alert("导入失败", isPresented: Binding(
            get: { importError != nil },
            set: { if !$0 { importError = nil } }
        )) {
            Button("好") { importError = nil }
        } message: {
            Text(importError ?? "")
        }
        .background(
            // 隐藏按钮承载全局快捷键
            Group {
                Button("Toggle Sidebar") { showSidebar.toggle() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Import") { showImportPicker = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    @MainActor
    private func handleImportResult(_ result: Result<URL, Error>) {
        switch result {
        case .success(let url):
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }
            do {
                _ = try library?.importBook(at: url)
            } catch {
                importError = error.localizedDescription
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

struct LoadingView: View {
    @Environment(ThemeManager.self) private var themeManager
    var body: some View {
        VStack(spacing: 12) {
            ProgressView()
            Text("加载中...")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct WelcomeView: View {
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "book")
                .font(.system(size: 64))
                .foregroundStyle(themeManager.currentTheme.accent)
            Text("选择一本书开始阅读")
                .font(.title2)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
            Text("按 ⌘O 导入书籍，或拖拽文件到侧边栏")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.contentBG)
    }
}
