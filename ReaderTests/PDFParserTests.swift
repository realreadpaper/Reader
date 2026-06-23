import XCTest
import PDFKit
@testable import Reader

final class PDFParserTests: XCTestCase {
    func testParseInvalidPathThrowsCorrupted() async throws {
        let url = URL(fileURLWithPath: "/dev/null")
        let parser = PDFParser()
        do {
            _ = try await parser.parse(fileAt: url)
            XCTFail("应抛错")
        } catch BookParseError.corruptedFile {
            // 通过
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    func testParseValidPDFReturnsPdfKitRenderer() async throws {
        let doc = PDFDocument()
        let page = PDFPage()
        doc.insert(page, at: 0)
        let pdfData = doc.dataRepresentation()!
        let tmp = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".pdf")
        try pdfData.write(to: tmp)
        defer { try? FileManager.default.removeItem(at: tmp) }

        let parsed = try await PDFParser().parse(fileAt: tmp)
        XCTAssertEqual(parsed.renderer, .pdfKit)
        XCTAssertNotNil(parsed.pdfDocument)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.toc.count, 1)
    }
}
