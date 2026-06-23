import XCTest
@testable import Reader

final class SearchPanelLayoutTests: XCTestCase {
    func testInitialEmptySearchPanelDoesNotReserveResultHeight() {
        XCTAssertNil(SearchPanelLayout.maxHeight(hasResultArea: false))
    }

    func testSearchPanelWithResultAreaReservesResultHeight() {
        XCTAssertEqual(SearchPanelLayout.maxHeight(hasResultArea: true), 200)
    }

    func testReaderPositionLabelUsesPagesForAllFormats() {
        XCTAssertEqual(
            ReaderPositionLabel.text(fileType: .epub, currentIndex: 2, total: 9, pdfCurrentPage: 0),
            "第 3 页 / 共 9 页"
        )
        XCTAssertEqual(
            ReaderPositionLabel.text(fileType: .mobi, currentIndex: 1, total: 12, pdfCurrentPage: 0),
            "第 2 页 / 共 12 页"
        )
        XCTAssertEqual(
            ReaderPositionLabel.text(fileType: .pdf, currentIndex: 0, total: 7, pdfCurrentPage: 4),
            "第 4 页 / 共 7 页"
        )
    }
}
