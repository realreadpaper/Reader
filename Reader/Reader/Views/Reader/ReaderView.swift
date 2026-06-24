import SwiftUI
import PDFKit

struct ReaderView: View {
    let book: Book
    let storageService: StorageService
    let library: BookLibrary

    @Environment(ThemeManager.self) private var themeManager
    @State private var settings = ReaderSettings()
    @State private var coordinator: RenderCoordinator
    @State private var selectionInfo: SelectionInfo?
    @State private var highlightToast: String?

    struct SelectionInfo: Identifiable, Equatable {
        let id = UUID()
        let text: String
        let location: CGPoint
    }

    init(book: Book, storageService: StorageService, library: BookLibrary) {
        self.book = book
        self.storageService = storageService
        self.library = library
        let coord = MainActor.assumeIsolated { RenderCoordinator(book: book, storageService: storageService) }
        _coordinator = State(initialValue: coord)
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                TopBarView(
                    book: book,
                    coordinator: coordinator,
                    storageService: storageService,
                    settings: settings,
                    onTOCToggle: { coordinator.showTOC.toggle() },
                    onSearchToggle: { coordinator.showSearch.toggle() },
                    onFontToggle: { coordinator.showFontPanel.toggle() },
                    onAnnotationsToggle: { coordinator.showAnnotations.toggle() }
                )

                HStack(spacing: 0) {
                    if coordinator.showTOC {
                        TOCView(
                            chapters: coordinator.tocEntries.map { ($0.title, $0.chapterIndex) },
                            onChapterSelect: { coordinator.navigateToChapter($0) },
                            showPageNumbers: true,
                            currentIndex: book.fileType == .pdf
                                ? coordinator.pdfCurrentPage - 1
                                : coordinator.currentChapter
                        )
                        .frame(width: 220)
                        .background(themeManager.currentTheme.sidebarBG)
                    }

                    mainRenderer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(themeManager.currentTheme.contentBG)
                        .overlay(alignment: .top) {
                            if coordinator.isLoading {
                                LoadingOverlay()
                            }
                        }
                }

                BottomBarView(book: book, coordinator: coordinator)
            }
            .background(themeManager.currentTheme.contentBG)

            if let info = selectionInfo {
                HighlightMenuView(
                    selectedText: info.text,
                    onHighlight: { color in handleHighlight(color, info: info) },
                    onCopy: {
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(info.text, forType: .string)
                        selectionInfo = nil
                    },
                    onDelete: { selectionInfo = nil }
                )
                .position(x: max(120, min(info.location.x, (NSScreen.main?.frame.width ?? 800) - 120)),
                          y: max(60, info.location.y - 30))
                .transition(.opacity)
                .zIndex(10)
            }

            if coordinator.showFontPanel {
                FontPanelOverlay(
                    settings: settings,
                    fileType: book.fileType,
                    onClose: { coordinator.showFontPanel = false }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(5)
            }

            if coordinator.showSearch {
                SearchPanelOverlay(
                    coordinator: coordinator,
                    onResultSelect: { handleSearchResult($0) },
                    onClose: { coordinator.showSearch = false }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(5)
            }

            if coordinator.showAnnotations {
                AnnotationPanelOverlay(
                    highlights: storageService.fetchHighlights(for: book),
                    bookmarks: storageService.fetchBookmarks(for: book),
                    onClose: { coordinator.showAnnotations = false },
                    onHighlightSelect: { navigateToHighlight($0) },
                    onHighlightDelete: { highlight in
                        storageService.deleteHighlight(highlight)
                    },
                    onBookmarkSelect: { navigateToBookmark($0) },
                    onBookmarkDelete: { bookmark in
                        storageService.deleteBookmark(bookmark)
                    }
                )
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(5)
            }

            if let toast = highlightToast {
                VStack {
                    Spacer()
                    Text(toast)
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.black.opacity(0.7))
                        .foregroundStyle(.white)
                        .cornerRadius(6)
                        .padding(.bottom, 40)
                }
                .zIndex(20)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: coordinator.showFontPanel)
        .animation(.easeInOut(duration: 0.2), value: coordinator.showSearch)
        .animation(.easeInOut(duration: 0.2), value: coordinator.showTOC)
        .animation(.easeInOut(duration: 0.2), value: coordinator.showAnnotations)
        .animation(.easeInOut(duration: 0.15), value: selectionInfo)
        .task {
            await coordinator.load()
            storageService.updateBook(book)
        }
        .alert("无法打开", isPresented: Binding(
            get: { coordinator.loadError != nil },
            set: { if !$0 { coordinator.loadError = nil } }
        )) {
            Button("好") { coordinator.loadError = nil }
        } message: {
            Text(coordinator.loadError ?? "")
        }
        .onChange(of: highlightToast) { _, _ in
            if highlightToast != nil {
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    withAnimation { highlightToast = nil }
                }
            }
        }
    }

    @MainActor
    @ViewBuilder
    private var mainRenderer: some View {
        switch book.fileType {
        case .epub, .mobi:
            if !coordinator.chapters.isEmpty {
                EPUBRendererView(
                    book: book,
                    chapters: coordinator.chapters,
                    resourceDirectory: coordinator.resourceDirectory,
                    currentChapter: $coordinator.currentChapter,
                    themeManager: themeManager,
                    settings: settings,
                    initialProgress: coordinator.progress,
                    onPageMetrics: { coordinator.updateEPUBProgress($0) },
                    onSelection: { text, rect in
                        handleSelection(text: text, rect: rect)
                    }
                )
            } else if coordinator.loadError != nil {
                EmptyView()
            } else {
                Text("加载中...")
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
            }
        case .pdf:
            PDFRendererView(
                book: book,
                coordinator: coordinator,
                settings: settings,
                onSelection: { text, rect in
                    handleSelection(text: text, rect: rect)
                }
            )
        case .txt:
            if !coordinator.chapters.isEmpty {
                TXTRendererView(
                    book: book,
                    chapters: coordinator.chapters,
                    currentChapter: $coordinator.currentChapter,
                    progress: $coordinator.progress,
                    themeManager: themeManager,
                    settings: settings,
                    onSelection: { text, rect in
                        handleSelection(text: text, rect: rect)
                    }
                )
            } else {
                Text("加载中...")
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
            }
        case .md:
            if !coordinator.chapters.isEmpty {
                MDRendererView(
                    book: book,
                    chapters: coordinator.chapters,
                    currentChapter: $coordinator.currentChapter,
                    progress: $coordinator.progress,
                    themeManager: themeManager,
                    storageService: storageService,
                    settings: settings,
                    onSelection: { text, rect in
                        handleSelection(text: text, rect: rect)
                    }
                )
            } else {
                Text("加载中...")
                    .foregroundStyle(themeManager.currentTheme.secondaryText)
            }
        }
    }

    // MARK: - Selection handling

    @MainActor
    private func handleSelection(text: String, rect: CGRect) {
        guard !text.isEmpty else {
            selectionInfo = nil
            return
        }
        guard let window = NSApp.keyWindow,
              let contentView = window.contentView else { return }
        let windowFrame = contentView.frame
        let location = CGPoint(x: rect.midX, y: windowFrame.height - rect.minY)
        withAnimation(.easeInOut(duration: 0.15)) {
            selectionInfo = SelectionInfo(text: text, location: location)
        }
    }

    @MainActor
    private func handleHighlight(_ color: HighlightColor, info: SelectionInfo) {
        let chapterTitle = coordinator.currentTitle
        let offsetBase = ReaderNavigationPosition.highlightStartOffset(
            fileType: book.fileType,
            currentChapter: coordinator.currentChapter,
            pdfCurrentPage: coordinator.pdfCurrentPage
        )

        _ = storageService.addHighlight(
            to: book,
            text: info.text,
            color: color,
            startOffset: offsetBase,
            endOffset: offsetBase + info.text.count,
            chapter: chapterTitle
        )

        applyHighlightInWebView(color: color)
        selectionInfo = nil
        withAnimation {
            highlightToast = "已添加高亮"
        }
    }

    @MainActor
    private func applyHighlightInWebView(color: HighlightColor) {
        let className = "reader-highlight-\(color.rawValue)"
        NotificationCenter.default.post(
            name: .applyHighlightRequest,
            object: nil,
            userInfo: ["className": className]
        )
    }

    @MainActor
    private func navigateToBookmark(_ bookmark: Bookmark) {
        coordinator.showAnnotations = false
        guard let target = ReaderNavigationPosition.parse(bookmark.position) else { return }

        switch target {
        case .pdfPage(let pageIndex):
            coordinator.navigateToChapter(pageIndex)
        case .pagedContent(let chapterIndex, let progress):
            coordinator.navigateToChapter(chapterIndex)
            if let progress {
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NotificationCenter.default.post(
                        name: .epubRestoreProgress,
                        object: nil,
                        userInfo: ["progress": progress]
                    )
                }
            }
        }
    }

    @MainActor
    private func navigateToHighlight(_ highlight: Highlight) {
        coordinator.showAnnotations = false
        switch book.fileType {
        case .pdf:
            // For PDF, startOffset encodes the page index: chapter * 1_000_000 + offset
            let pageIndex = highlight.startOffset / 1_000_000
            coordinator.navigateToChapter(pageIndex)
        case .epub, .mobi, .txt, .md:
            if let chapterStr = highlight.chapter,
               let chapterIndex = coordinator.tocEntries.firstIndex(where: { $0.title == chapterStr }) {
                coordinator.navigateToChapter(chapterIndex)
            } else {
                let chapterIndex = highlight.startOffset / 1_000_000
                if chapterIndex >= 0 && chapterIndex < coordinator.chapters.count {
                    coordinator.navigateToChapter(chapterIndex)
                }
            }
        }
    }

    @MainActor
    private func handleSearchResult(_ result: SearchResultTarget) {
        switch result {
        case .epubSearch(let index, let query):
            coordinator.navigateToChapter(index)
            NotificationCenter.default.post(
                name: .epubSearchRequest,
                object: nil,
                userInfo: ["chapterIndex": index, "query": query]
            )
            coordinator.showSearch = false
        case .pdfPage(let pageIndex):
            coordinator.navigateToChapter(pageIndex)
            coordinator.showSearch = false
        }
    }
}

enum SearchResultTarget {
    case epubSearch(chapterIndex: Int, query: String)
    case pdfPage(Int)
}

// MARK: - Loading

struct LoadingOverlay: View {
    @Environment(ThemeManager.self) private var themeManager
    var body: some View {
        VStack(spacing: 8) {
            ProgressView()
            Text("加载中...")
                .font(.caption)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .cornerRadius(8)
    }
}

// MARK: - Font panel overlay

struct FontPanelOverlay: View {
    @Bindable var settings: ReaderSettings
    let fileType: FileType
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .trailing) {
            Color.black.opacity(0.01)
                .onTapGesture { onClose() }
            FontPanelView(
                fontSize: $settings.fontSize,
                lineHeight: $settings.lineHeight,
                selectedTheme: .constant(.kraft),
                pdfFilterEnabled: $settings.pdfFilterEnabled,
                fileType: fileType,
                onClose: onClose
            )
            .frame(maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            .padding(.trailing, 12)
        }
    }
}

// MARK: - Search panel overlay

struct SearchPanelOverlay: View {
    let coordinator: RenderCoordinator
    let onResultSelect: (SearchResultTarget) -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.01)
                .onTapGesture { onClose() }
            SearchPanelView(
                coordinator: coordinator,
                onResultSelect: onResultSelect,
                onClose: onClose
            )
            .padding(.leading, 220)
            .padding(.trailing, 12)
        }
    }
}

// MARK: - Annotation panel overlay

struct AnnotationPanelOverlay: View {
    let highlights: [Highlight]
    let bookmarks: [Bookmark]
    let onClose: () -> Void
    let onHighlightSelect: (Highlight) -> Void
    let onHighlightDelete: (Highlight) -> Void
    let onBookmarkSelect: (Bookmark) -> Void
    let onBookmarkDelete: (Bookmark) -> Void

    @Environment(ThemeManager.self) private var themeManager
    @State private var selectedTab: Tab = .highlights

    enum Tab: String, CaseIterable {
        case highlights = "高亮"
        case bookmarks = "书签"
    }

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.01)
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                Picker("", selection: $selectedTab) {
                    ForEach(Tab.allCases, id: \.self) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .padding(10)

                switch selectedTab {
                case .highlights:
                    if highlights.isEmpty {
                        EmptyStateView(text: "暂无高亮")
                    } else {
                        AnnotationView(highlights: highlights, onHighlightSelect: onHighlightSelect)
                            .frame(maxHeight: .infinity)
                    }
                case .bookmarks:
                    if bookmarks.isEmpty {
                        EmptyStateView(text: "暂无书签")
                    } else {
                        BookmarkListView(bookmarks: bookmarks, onSelect: onBookmarkSelect, onDelete: onBookmarkDelete)
                            .frame(maxHeight: .infinity)
                    }
                }
            }
            .frame(width: 260)
            .background(themeManager.currentTheme.sidebarBG)
            .shadow(color: .black.opacity(0.15), radius: 8)
        }
    }
}

struct EmptyStateView: View {
    let text: String
    @Environment(ThemeManager.self) private var themeManager
    var body: some View {
        VStack {
            Spacer()
            Text(text)
                .foregroundStyle(themeManager.currentTheme.secondaryText)
                .font(.caption)
            Spacer()
        }
    }
}

// MARK: - Bookmark list

struct BookmarkListView: View {
    let bookmarks: [Bookmark]
    let onSelect: (Bookmark) -> Void
    let onDelete: (Bookmark) -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        List {
            ForEach(bookmarks, id: \.id) { bookmark in
                HStack {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(bookmark.chapter ?? "未知页")
                                .font(.subheadline)
                                .foregroundStyle(themeManager.currentTheme.primaryText)
                            Text(bookmark.note ?? bookmark.position)
                                .font(.caption)
                                .foregroundStyle(themeManager.currentTheme.secondaryText)
                                .lineLimit(2)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { onSelect(bookmark) }

                    Button(action: { onDelete(bookmark) }) {
                        Image(systemName: "trash")
                            .foregroundStyle(.red.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.vertical, 4)
            }
        }
        .listStyle(.sidebar)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let applyHighlightRequest = Notification.Name("applyHighlightRequest")
    static let epubSearchRequest = Notification.Name("epubSearchRequest")
    static let epubRestoreProgress = Notification.Name("epubRestoreProgress")
}
