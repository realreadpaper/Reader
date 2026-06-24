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
    @State private var annotationRefreshToken = UUID()

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
                    onAnnotationsToggle: { coordinator.showAnnotations.toggle() },
                    onBookmarkAdded: { annotationRefreshToken = UUID() }
                )

                ZStack(alignment: .leading) {
                    mainRenderer
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(themeManager.currentTheme.contentBG)
                        .overlay(alignment: .top) {
                            if coordinator.isLoading {
                                LoadingOverlay()
                            }
                        }

                    if coordinator.showTOC {
                        TOCPanelOverlay(
                            chapters: coordinator.tocEntries.map { ($0.title, $0.chapterIndex) },
                            currentIndex: book.fileType == .pdf
                                ? coordinator.pdfCurrentPage - 1
                                : coordinator.currentChapter,
                            onChapterSelect: { chapterIndex in
                                coordinator.navigateToChapter(chapterIndex)
                                coordinator.showTOC = false
                            },
                            onClose: { coordinator.showTOC = false }
                        )
                        .transition(.move(edge: .leading).combined(with: .opacity))
                        .zIndex(4)
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
                    refreshToken: annotationRefreshToken,
                    bookmarks: storageService.fetchBookmarks(for: book),
                    onClose: { coordinator.showAnnotations = false },
                    onBookmarkSelect: { navigateToBookmark($0) },
                    onBookmarkDelete: { bookmark in
                        storageService.deleteBookmark(bookmark)
                        annotationRefreshToken = UUID()
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
            postRestoreHighlights()
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
                    },
                    onPageReady: { postRestoreHighlights() }
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
                    },
                    onPageReady: { postRestoreHighlights() }
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
                    },
                    onPageReady: { postRestoreHighlights() }
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
        let range = ReaderNavigationPosition.highlightRange(
            startOffset: offsetBase,
            selectedText: info.text
        )

        _ = storageService.addHighlight(
            to: book,
            text: info.text,
            color: color,
            startOffset: range.start,
            endOffset: range.end,
            chapter: chapterTitle
        )

        applyHighlightInWebView(color: color)
        annotationRefreshToken = UUID()
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
    func postRestoreHighlights() {
        let highlights = storageService.fetchHighlights(for: book)
        NotificationCenter.default.post(
            name: .restoreHighlights,
            object: nil,
            userInfo: ["highlights": highlights]
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

// MARK: - TOC overlay

struct TOCPanelOverlay: View {
    let chapters: [(title: String, chapterIndex: Int)]
    let currentIndex: Int
    let onChapterSelect: (Int) -> Void
    let onClose: () -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.01)
                .onTapGesture { onClose() }

            TOCView(
                chapters: chapters,
                onChapterSelect: onChapterSelect,
                showPageNumbers: true,
                currentIndex: currentIndex
            )
            .frame(width: 220)
            .frame(maxHeight: .infinity)
            .background(TOCStyle.background(for: themeManager.currentTheme))
            .shadow(color: .black.opacity(0.15), radius: 8)
        }
    }
}

// MARK: - Annotation panel overlay

struct AnnotationPanelOverlay: View {
    let refreshToken: UUID
    let bookmarks: [Bookmark]
    let onClose: () -> Void
    let onBookmarkSelect: (Bookmark) -> Void
    let onBookmarkDelete: (Bookmark) -> Void

    @Environment(ThemeManager.self) private var themeManager

    var body: some View {
        ZStack(alignment: .leading) {
            Color.black.opacity(0.01)
                .onTapGesture { onClose() }
            VStack(spacing: 0) {
                HStack {
                    Text("书签")
                        .font(.headline)
                        .foregroundStyle(themeManager.currentTheme.primaryText)
                    Spacer()
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(themeManager.currentTheme.secondaryText)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 12)

                Divider()
                    .background(themeManager.currentTheme.border)

                Group {
                    if bookmarks.isEmpty {
                        EmptyStateView(text: "暂无书签")
                    } else {
                        BookmarkListView(bookmarks: bookmarks, onSelect: onBookmarkSelect, onDelete: onBookmarkDelete)
                            .frame(maxHeight: .infinity)
                    }
                }
                .id(refreshToken)
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
                .listRowBackground(Color.clear)
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(themeManager.currentTheme.sidebarBG)
    }
}

// MARK: - Notifications

extension Notification.Name {
    static let applyHighlightRequest = Notification.Name("applyHighlightRequest")
    static let epubSearchRequest = Notification.Name("epubSearchRequest")
    static let epubRestoreProgress = Notification.Name("epubRestoreProgress")
    static let restoreHighlights = Notification.Name("restoreHighlights")
    static let scrollToHighlight = Notification.Name("scrollToHighlight")
}
