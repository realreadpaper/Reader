import SwiftUI
import SwiftData
import UniformTypeIdentifiers

private let supportedImportTypes: [UTType] = {
    var types: [UTType] = []
    if let epub = UTType(filenameExtension: "epub") { types.append(epub) }
    if let mobi = UTType(filenameExtension: "mobi") { types.append(mobi) }
    if let pdf = UTType(filenameExtension: "pdf") { types.append(pdf) }
    if let txt = UTType(filenameExtension: "txt") { types.append(txt) }
    if let md = UTType(filenameExtension: "md") { types.append(md) }
    if let markdown = UTType(filenameExtension: "markdown") { types.append(markdown) }
    return types
}()

enum ReaderViewIdentity {
    static func id(for book: Book) -> UUID {
        book.id
    }
}

enum SidebarLayoutPolicy {
    static let minWidth: CGFloat = 220
    static let preferredWidth: CGFloat = 280
    static let maxWidth: CGFloat = 280
}

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(ThemeManager.self) private var themeManager

    @State private var selectedBook: Book?
    @State private var showSidebar = true
    @State private var sidebarWidth: CGFloat = SidebarLayoutPolicy.preferredWidth
    @State private var storageService: StorageService?
    @State private var library: BookLibrary?
    @State private var importError: String?
    @State private var showImportPicker = false

    var body: some View {
        Group {
            if let storageService, let library {
                HStack(spacing: 0) {
                    sidebarPane(
                        storageService: storageService,
                        library: library
                    )

                    if let book = selectedBook {
                        ReaderView(
                            book: book,
                            storageService: storageService,
                            library: library
                        )
                        .id(ReaderViewIdentity.id(for: book))
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    } else {
                        WelcomeView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .background(themeManager.currentTheme.contentBG)
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
                Button("Toggle Sidebar") { toggleSidebar() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                Button("Import") { showImportPicker = true }
                    .keyboardShortcut("o", modifiers: .command)
            }
            .opacity(0)
            .frame(width: 0, height: 0)
        )
    }

    @ViewBuilder
    private func sidebarPane(storageService: StorageService, library: BookLibrary) -> some View {
        if showSidebar {
            HStack(spacing: 0) {
                SidebarView(
                    storageService: storageService,
                    library: library,
                    selectedBook: $selectedBook,
                    onRequestImport: { showImportPicker = true },
                    onToggleSidebar: { collapseSidebar() },
                    importError: $importError
                )

                SidebarResizeHandle(width: $sidebarWidth)
            }
            .frame(width: sidebarWidth)
        } else {
            CollapsedSidebarRail(onExpand: { expandSidebar() })
                .frame(width: 44)
        }
    }

    private func toggleSidebar() {
        showSidebar ? collapseSidebar() : expandSidebar()
    }

    private func collapseSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showSidebar = false
        }
    }

    private func expandSidebar() {
        withAnimation(.easeInOut(duration: 0.18)) {
            showSidebar = true
        }
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

private struct CollapsedSidebarRail: View {
    let onExpand: () -> Void
    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        VStack {
            Button(action: onExpand) {
                Image(systemName: "sidebar.left")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(themeManager.currentTheme.sidebarBG.opacity(0.94))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(themeManager.currentTheme.border.opacity(0.8), lineWidth: 0.5)
                    )
            }
            .buttonStyle(.plain)
            .help("展开书架 (⇧⌘S)")
            .padding(.top, 10)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(themeManager.currentTheme.sidebarBG)
    }
}

private struct SidebarResizeHandle: View {
    @Binding var width: CGFloat
    @Environment(ThemeManager.self) private var themeManager
    @State private var dragStartWidth: CGFloat?

    var body: some View {
        Rectangle()
            .fill(themeManager.currentTheme.border.opacity(0.7))
            .frame(width: 1)
            .overlay(
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: 8)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let startWidth = dragStartWidth ?? width
                                dragStartWidth = startWidth
                                width = min(
                                    SidebarLayoutPolicy.maxWidth,
                                    max(SidebarLayoutPolicy.minWidth, startWidth + value.translation.width)
                                )
                            }
                            .onEnded { _ in
                                dragStartWidth = nil
                            }
                    )
            )
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
