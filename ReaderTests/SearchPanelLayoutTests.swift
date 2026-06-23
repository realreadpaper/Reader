import XCTest
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
}
