import XCTest
import AppKit
import SwiftData
@testable import Reader

final class SearchPanelLayoutTests: XCTestCase {
    func testInitialEmptySearchPanelDoesNotReserveResultHeight() {
        XCTAssertNil(SearchPanelLayout.maxHeight(hasResultArea: false))
    }

    func testSearchPanelWithResultAreaReservesResultHeight() {
        XCTAssertEqual(SearchPanelLayout.maxHeight(hasResultArea: true), 200)
    }

    func testSearchInputChangeTriggersAutomaticSearch() {
        XCTAssertTrue(SearchInputPolicy.shouldSearchAutomatically(previous: "", current: "logic"))
        XCTAssertFalse(SearchInputPolicy.shouldSearchAutomatically(previous: "logic", current: "logic"))
    }

    func testReaderViewIdentityChangesBetweenBooks() {
        let first = Book(title: "A", filePath: "/tmp/a.pdf", fileType: .pdf)
        let second = Book(title: "B", filePath: "/tmp/b.pdf", fileType: .pdf)

        XCTAssertNotEqual(ReaderViewIdentity.id(for: first), ReaderViewIdentity.id(for: second))
    }

    func testSidebarDefaultWidthUsesComfortableBookshelfLayout() {
        XCTAssertEqual(SidebarLayoutPolicy.preferredWidth, SidebarLayoutPolicy.maxWidth)
        XCTAssertGreaterThan(SidebarLayoutPolicy.preferredWidth, SidebarLayoutPolicy.minWidth)
    }

    func testEPUBProgressUsesWholeBookPageCount() {
        XCTAssertEqual(
            EPUBProgressPolicy.overallProgress(currentPage: 0, totalPages: 10),
            0.1,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            EPUBProgressPolicy.overallProgress(currentPage: 9, totalPages: 10),
            1,
            accuracy: 0.0001
        )
    }

    func testEPUBProgressRestoresChapterFromSavedWholeBookProgress() {
        XCTAssertEqual(EPUBProgressPolicy.restoredPage(savedProgress: 0.3, totalPages: 10), 2)
        XCTAssertEqual(EPUBProgressPolicy.restoredPage(savedProgress: 1, totalPages: 10), 9)
        XCTAssertEqual(EPUBProgressPolicy.restoredPage(savedProgress: 0, totalPages: 10), 0)
    }

    func testEPUBBookWrapperCombinesChaptersAndRewritesRelativeResources() {
        let chapters = [
            EPUBChapter(
                title: "One",
                htmlContent: #"<html><body><p>One</p><img src="../images/one.jpeg"/></body></html>"#,
                fileName: "text/part0001.html",
                spineIndex: 0
            ),
            EPUBChapter(
                title: "Two",
                htmlContent: #"<html><body id="chapter-two"><p>Two</p></body></html>"#,
                fileName: "text/part0002.html",
                spineIndex: 1
            )
        ]

        let html = EPUBScripts.wrapBookHTML(
            chapters: chapters,
            theme: .kraft,
            fontSize: 18,
            lineHeight: 2.0
        )

        XCTAssertTrue(html.contains(#"data-reader-chapter="0""#))
        XCTAssertTrue(html.contains(#"data-reader-chapter="1""#))
        XCTAssertTrue(html.contains(#"src="images/one.jpeg""#))
        XCTAssertTrue(html.contains(#"id="chapter-two""#))
    }

    func testEPUBPagingScriptTurnsWholePagesFromWheelAndKeyboard() {
        XCTAssertTrue(EPUBScripts.bootScript.contains("window.ReaderTurnPage"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("wheelAccumulator"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("keydown"))
    }

    func testEPUBPagingScriptRealignsPageAfterViewportResize() {
        XCTAssertTrue(EPUBScripts.bootScript.contains("lastReportedPage"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("realignAfterResize"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("ResizeObserver"))
    }

    func testEPUBPagingCSSUsesResponsivePageMetrics() {
        XCTAssertTrue(EPUBScripts.cssTemplate.contains("--reader-page-padding-x: clamp"))
        XCTAssertTrue(EPUBScripts.cssTemplate.contains("--reader-page-width: calc(100vw - var(--reader-page-padding-x) - var(--reader-page-padding-x))"))
        XCTAssertTrue(EPUBScripts.cssTemplate.contains("column-width: var(--reader-page-width)"))
        XCTAssertTrue(EPUBScripts.cssTemplate.contains("column-gap: var(--reader-column-gap)"))
    }

    func testEPUBPagingPreservesReadingProgressAfterReflow() {
        XCTAssertTrue(EPUBScripts.bootScript.contains("lastKnownProgress"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("pageForProgress"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("setTimeout(realignAfterResize, 80)"))
    }

    func testReaderPositionLabelUsesPagesForAllFormats() {
        XCTAssertEqual(
            ReaderPositionLabel.text(currentPage: 3, total: 9),
            "第 3 页 / 共 9 页"
        )
        XCTAssertEqual(
            ReaderPositionLabel.text(currentPage: 2, total: 12),
            "第 2 页 / 共 12 页"
        )
        XCTAssertEqual(
            ReaderPositionLabel.text(currentPage: 4, total: 7),
            "第 4 页 / 共 7 页"
        )
    }

    func testBookRowSelectionStyleKeepsTitleReadable() {
        XCTAssertEqual(BookRowSelectionStyle.titleHex(theme: .kraft, isSelected: false), "#1A1208")
        XCTAssertEqual(BookRowSelectionStyle.titleHex(theme: .kraft, isSelected: true), "#1A1208")
        XCTAssertEqual(BookRowSelectionStyle.backgroundHex(theme: .kraft, isSelected: true), "#D5C8B0")
    }

    func testAppBundleDeclaresSupportedDocumentTypesForFinderOpenWith() throws {
        let info = Bundle.main.infoDictionary ?? [:]
        let documentTypes = try XCTUnwrap(info["CFBundleDocumentTypes"] as? [[String: Any]])
        let importedTypes = (info["UTImportedTypeDeclarations"] as? [[String: Any]]) ?? []

        let declaredExtensions = Set(documentTypes.flatMap { entry -> [String] in
            let legacyExtensions = entry["CFBundleTypeExtensions"] as? [String] ?? []
            return legacyExtensions.map { $0.lowercased() }
        })
        let declaredUTIs = Set(documentTypes.flatMap { entry -> [String] in
            entry["LSItemContentTypes"] as? [String] ?? []
        })
        let importedUTIs = Set(importedTypes.compactMap { $0["UTTypeIdentifier"] as? String })

        XCTAssertTrue(declaredExtensions.isSuperset(of: ["epub", "mobi", "pdf", "txt", "md", "markdown", "azw", "azw3"]))
        XCTAssertTrue(declaredUTIs.isSuperset(of: [
            "org.idpf.epub-container",
            "com.amazon.mobi",
            "com.amazon.azw",
            "com.amazon.azw3",
            "com.adobe.pdf",
            "public.plain-text",
            "net.daringfireball.markdown"
        ]))
        XCTAssertTrue(importedUTIs.isSuperset(of: ["com.amazon.mobi", "com.amazon.azw", "com.amazon.azw3"]))
    }

    func testAppDelegatePublishesFinderOpenFiles() {
        let delegate = AppDelegate()
        let url = URL(fileURLWithPath: "/tmp/opened-from-finder.mobi")
        var openedURLs: [URL] = []
        let token = NotificationCenter.default.addObserver(
            forName: .readerOpenFiles,
            object: nil,
            queue: nil
        ) { notification in
            openedURLs = notification.userInfo?["urls"] as? [URL] ?? []
        }
        defer { NotificationCenter.default.removeObserver(token) }

        delegate.application(NSApplication.shared, openFiles: [url.path])

        XCTAssertEqual(openedURLs, [url])
    }

    @MainActor
    func testStagedProgressUpdatesBookImmediatelyForShelf() throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = StorageService(modelContext: container.mainContext)
        let book = Book(title: "Progress", filePath: "/tmp/progress.epub", fileType: .epub)

        service.stageProgress(book, progress: 0.42)

        XCTAssertEqual(book.progress, 0.42, accuracy: 0.0001)
        XCTAssertEqual(service.libraryRevision, 1)
    }

    @MainActor
    func testToggleFavoritePersistsAndRefreshesLibraryRevision() throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = StorageService(modelContext: container.mainContext)
        let book = service.addBook(title: "Favorite", filePath: "/tmp/favorite.epub", fileType: .epub)
        let revisionAfterImport = service.libraryRevision

        service.toggleFavorite(book)

        XCTAssertTrue(book.isFavorite)
        XCTAssertGreaterThan(service.libraryRevision, revisionAfterImport)
        XCTAssertEqual(service.fetchFavoriteBooks().map(\.id), [book.id])
    }

    @MainActor
    func testToggleFavoriteAgainRemovesBookFromFavorites() throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let service = StorageService(modelContext: container.mainContext)
        let book = service.addBook(title: "Favorite", filePath: "/tmp/favorite.epub", fileType: .epub)

        service.toggleFavorite(book)
        service.toggleFavorite(book)

        XCTAssertFalse(book.isFavorite)
        XCTAssertTrue(service.fetchFavoriteBooks().isEmpty)
    }

    func testProgressRestoreGuardIgnoresInitialZeroReportWhenSavedProgressExists() {
        var guardState = ProgressRestoreGuard(savedProgress: 0.58)

        XCTAssertFalse(guardState.shouldAcceptReportedProgress(0))
        XCTAssertFalse(guardState.shouldAcceptReportedProgress(0.2))
        XCTAssertTrue(guardState.shouldAcceptReportedProgress(0.58))
        XCTAssertTrue(guardState.shouldAcceptReportedProgress(0.6))
    }

    func testTOCStyleUsesOpaqueThemeBackgroundAndReadableText() {
        XCTAssertEqual(TOCStyle.backgroundHex(for: .kraft), "#E8DCC8")
        XCTAssertEqual(TOCStyle.primaryTextHex(for: .kraft), "#1A1208")
        XCTAssertEqual(TOCStyle.secondaryTextHex(for: .night), "#C0B090")
    }

    func testReaderNavigationPositionStoresPDFBookmarksAsZeroBasedPageIndexes() {
        let position = ReaderNavigationPosition.bookmarkPosition(
            fileType: .pdf,
            currentChapter: 0,
            pdfCurrentPage: 3,
            progress: 0.3
        )

        XCTAssertEqual(position, "pdfPage:2")
        XCTAssertEqual(ReaderNavigationPosition.parse(position), .pdfPage(2))
    }

    func testReaderNavigationPositionStoresHighlightEndAfterSelectedText() {
        let range = ReaderNavigationPosition.highlightRange(
            startOffset: 2_000_000,
            selectedText: "简单的逻辑学"
        )

        XCTAssertEqual(range.start, 2_000_000)
        XCTAssertEqual(range.end, 2_000_006)
    }

    func testReaderNavigationPositionParsesLegacyPDFBookmarksAsOneBasedPages() {
        XCTAssertEqual(ReaderNavigationPosition.parse("pdf:1"), .pdfPage(0))
        XCTAssertEqual(ReaderNavigationPosition.parse("pdf:3"), .pdfPage(2))
    }

    func testReaderNavigationPositionStoresPagedFormatsWithChapterAndProgress() {
        let position = ReaderNavigationPosition.bookmarkPosition(
            fileType: .epub,
            currentChapter: 4,
            pdfCurrentPage: 0,
            progress: 0.42
        )

        XCTAssertEqual(position, "epub:4:0.42")
        XCTAssertEqual(
            ReaderNavigationPosition.parse(position),
            .pagedContent(chapterIndex: 4, progress: 0.42)
        )
    }

    @MainActor
    func testEPUBSearchDecodesHTMLEntitiesAndIgnoresHiddenMarkup() async throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = Book(title: "EPUB", filePath: "/tmp/book.epub", fileType: .epub)
        let coordinator = RenderCoordinator(
            book: book,
            storageService: StorageService(modelContext: container.mainContext)
        )
        coordinator.epubMetadata = EPUBMetadata(
            title: "EPUB",
            author: nil,
            chapters: [
                EPUBChapter(
                    title: "Chapter",
                    htmlContent: """
                    <html><head><style>.hidden{content:'隐藏命中'}</style><script>var x='隐藏命中';</script></head>
                    <body><p>逻辑&amp;思维&nbsp;能力来自&#x4E2D;&#22269;经验。</p></body></html>
                    """,
                    fileName: "chapter.xhtml",
                    spineIndex: 0
                )
            ],
            tocEntries: [],
            resourceDirectory: URL(fileURLWithPath: "/tmp")
        )

        let decodedResults = await coordinator.searchEPUB("逻辑&思维 能力来自中国")
        XCTAssertEqual(decodedResults.count, 1)
        guard !decodedResults.isEmpty else { return }
        XCTAssertTrue(decodedResults[0].snippet.contains("逻辑&思维 能力来自中国"))

        let hiddenResults = await coordinator.searchEPUB("隐藏命中")
        XCTAssertTrue(hiddenResults.isEmpty)
    }

    @MainActor
    func testBlockingLoadingOverlayHidesOnceChaptersAreAvailable() async throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = Book(title: "MOBI", filePath: "/tmp/book.mobi", fileType: .mobi)
        let coordinator = RenderCoordinator(
            book: book,
            storageService: StorageService(modelContext: container.mainContext)
        )

        coordinator.isLoading = true
        XCTAssertTrue(coordinator.shouldShowBlockingLoadingOverlay)

        coordinator.epubMetadata = EPUBMetadata(
            title: "Book",
            author: nil,
            chapters: [
                EPUBChapter(
                    title: "Chapter",
                    htmlContent: "<p>先显示的内容</p>",
                    fileName: "chapter.xhtml",
                    spineIndex: 0
                )
            ],
            tocEntries: [],
            resourceDirectory: FileManager.default.temporaryDirectory
        )

        XCTAssertFalse(coordinator.shouldShowBlockingLoadingOverlay)
    }

    @MainActor
    func testCurrentTitleUsesTOCChapterIndexInsteadOfTOCArrayOffset() async throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = Book(title: "MOBI", filePath: "/tmp/book.mobi", fileType: .mobi)
        let coordinator = RenderCoordinator(
            book: book,
            storageService: StorageService(modelContext: container.mainContext)
        )
        coordinator.epubMetadata = EPUBMetadata(
            title: "Book",
            author: nil,
            chapters: (0..<8).map {
                EPUBChapter(
                    title: "第 \($0 + 1) 页",
                    htmlContent: "<p>\($0)</p>",
                    fileName: "chapter-\($0).xhtml",
                    spineIndex: $0
                )
            },
            tocEntries: [
                EPUBTOCEntry(title: "《活着就为改变世界》", chapterIndex: 0),
                EPUBTOCEntry(title: "扉页", chapterIndex: 1),
                EPUBTOCEntry(title: "目录", chapterIndex: 2),
                EPUBTOCEntry(title: "引语", chapterIndex: 3),
                EPUBTOCEntry(title: "序", chapterIndex: 4),
                EPUBTOCEntry(title: "[5]", chapterIndex: 30),
                EPUBTOCEntry(title: "改变世界的梦想者", chapterIndex: 5)
            ],
            resourceDirectory: FileManager.default.temporaryDirectory
        )
        coordinator.currentChapter = 5

        XCTAssertEqual(coordinator.currentTitle, "改变世界的梦想者")
    }

    @MainActor
    func testDisplayTOCEntriesIgnoreBrokenGeneratedAndOutOfRangeItems() async throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = Book(title: "MOBI", filePath: "/tmp/book.mobi", fileType: .mobi)
        let coordinator = RenderCoordinator(
            book: book,
            storageService: StorageService(modelContext: container.mainContext)
        )
        coordinator.epubMetadata = EPUBMetadata(
            title: "Book",
            author: nil,
            chapters: [
                EPUBChapter(title: "第 1 页", htmlContent: "<p>0</p>", fileName: "0.xhtml", spineIndex: 0),
                EPUBChapter(title: "第 2 页", htmlContent: "<p>1</p>", fileName: "1.xhtml", spineIndex: 1),
                EPUBChapter(title: "第 3 页", htmlContent: "<p>2</p>", fileName: "2.xhtml", spineIndex: 2)
            ],
            tocEntries: [
                EPUBTOCEntry(title: "[5]", chapterIndex: 30),
                EPUBTOCEntry(title: "第 2 页", chapterIndex: 1),
                EPUBTOCEntry(title: "正文", chapterIndex: 1),
                EPUBTOCEntry(title: "第二章", chapterIndex: 2)
            ],
            resourceDirectory: FileManager.default.temporaryDirectory
        )

        XCTAssertEqual(
            coordinator.displayTOCEntries.map { "\($0.chapterIndex):\($0.title)" },
            ["1:正文", "2:第二章"]
        )
    }

    @MainActor
    func testLoadSkipsParserWhenContentAlreadyAvailable() async throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let book = Book(title: "MOBI", filePath: "/tmp/missing-book.mobi", fileType: .mobi)
        let coordinator = RenderCoordinator(
            book: book,
            storageService: StorageService(modelContext: container.mainContext)
        )
        coordinator.epubMetadata = EPUBMetadata(
            title: "Book",
            author: nil,
            chapters: [
                EPUBChapter(
                    title: "Chapter",
                    htmlContent: "<p>已加载内容</p>",
                    fileName: "chapter.xhtml",
                    spineIndex: 0
                )
            ],
            tocEntries: [],
            resourceDirectory: FileManager.default.temporaryDirectory
        )

        await coordinator.load()

        XCTAssertNil(coordinator.loadError)
        XCTAssertFalse(coordinator.isLoading)
        XCTAssertEqual(coordinator.chapters.count, 1)
    }

    func testEPUBSearchNavigationScriptCanLocateQueryWithinChapter() {
        XCTAssertTrue(EPUBScripts.bootScript.contains("ReaderGoToSearchResult"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("reader-search-hit"))
    }

    func testMDParserKeepsMarkdownAsSingleEditableDocument() async throws {
        let markdown = """
        # Reader 阅读器测试文档

        这是一份用于测试 **Markdown 渲染**功能的示例文件。

        ## 基本语法

        ### 文本格式

        `这是行内代码`

        ## 第二章

        这是第二章的内容。
        """
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("md")
        try markdown.write(to: url, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: url) }

        let parsed = try await MDParser().parse(fileAt: url)

        XCTAssertEqual(parsed.renderer, .markdown)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.toc.count, 1)
        XCTAssertTrue(parsed.chapters[0].rawMarkdown?.contains("# Reader 阅读器测试文档") == true)
        XCTAssertTrue(parsed.chapters[0].rawMarkdown?.contains("## 基本语法") == true)
        XCTAssertTrue(parsed.chapters[0].rawMarkdown?.contains("`这是行内代码`") == true)
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("<h1>Reader 阅读器测试文档</h1>"))
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("<p>这是一份用于测试 <strong>Markdown 渲染</strong>功能的示例文件。</p>"))
    }

    @MainActor
    func testBookLibraryImportsMarkdownExtensionAsMD() throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let storage = StorageService(modelContext: container.mainContext)
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let library = BookLibrary(storageService: storage, appSupportDirectory: appSupport)
        let source = appSupport.appendingPathComponent("note.markdown")
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try "# Title".write(to: source, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(at: appSupport) }

        let book = try library.importBook(at: source)

        XCTAssertEqual(book.fileType, .md)
    }

    func testParseCacheUsesShortFilenameSafeKeysForLongBookPaths() throws {
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        var nestedDir = tempDir
        for idx in 0..<6 {
            nestedDir.appendPathComponent(String(repeating: "longpath\(idx)", count: 8), isDirectory: true)
        }
        try FileManager.default.createDirectory(at: nestedDir, withIntermediateDirectories: true)
        let longNamedBook = nestedDir.appendingPathComponent("活着就为改变世界-" + String(repeating: "very-long-title", count: 12) + ".mobi")
        try Data("book".utf8).write(to: longNamedBook)

        let key = try XCTUnwrap(BookParseCache.shared.cacheKey(for: longNamedBook))

        XCTAssertLessThanOrEqual(key.count, 96)
        XCTAssertFalse(key.contains("/"))
        XCTAssertFalse(key.contains("+"))
        XCTAssertFalse(key.contains("="))
    }
}
