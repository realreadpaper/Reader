import XCTest
@testable import Reader

final class MOBIDecompressorTests: XCTestCase {
    func testNoCompressionReturnsInput() throws {
        let input = Data([0x01, 0x02, 0x03])
        let output = try MOBIDecompressor.decompress(input, compression: .none)
        XCTAssertEqual(output, input)
    }

    func testPalmDocLiteralRunCopiesControlBytes() throws {
        let input = Data([0x05, 0xC3, 0xA9, 0x00, 0x01, 0x08])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(output, Data([0xC3, 0xA9, 0x00, 0x01, 0x08]))
    }

    func testPalmDocThrowsWhenLiteralRunIsTruncated() {
        XCTAssertThrowsError(
            try MOBIDecompressor.decompress(Data([0x05, 0xC3, 0xA9]), compression: .palmDoc)
        ) { error in
            guard case BookParseError.corruptedFile(let detail) = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
            XCTAssertTrue(detail.contains("PalmDOC"))
            XCTAssertTrue(detail.contains("literal"))
        }
    }

    func testPalmDocBackReferenceCopiesFromPreviousOutput() throws {
        let input = Data([0x61, 0x62, 0x63, 0x20, 0x80, 0x20])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(String(data: output, encoding: .ascii), "abc abc")
    }

    func testPalmDocSpaceCompressionExpandsHighBytes() throws {
        let input = Data([0xC8, 0xE9])
        let output = try MOBIDecompressor.decompress(input, compression: .palmDoc)
        XCTAssertEqual(String(data: output, encoding: .ascii), " H i")
    }

    func testHuffRequiresDictionaryRecords() {
        XCTAssertThrowsError(
            try MOBIDecompressor.decompress(Data([0x00]), compression: .huff)
        ) { error in
            guard case BookParseError.corruptedFile(let detail) = error else {
                XCTFail("错误类型不对：\(error)")
                return
            }
            XCTAssertTrue(detail.contains("HUFF/CDIC"))
            XCTAssertTrue(detail.contains("dictionary"))
        }
    }
}
