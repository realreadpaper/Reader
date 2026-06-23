import XCTest
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

    func testEPUBSearchNavigationScriptCanLocateQueryWithinChapter() {
        XCTAssertTrue(EPUBScripts.bootScript.contains("ReaderGoToSearchResult"))
        XCTAssertTrue(EPUBScripts.bootScript.contains("reader-search-hit"))
    }
}
