import XCTest
@testable import Reader

final class EPUBParserMigrationTests: XCTestCase {
    func testParseProducesParsedBookMatchingLegacyMetadata() async throws {
        let testFile = URL(fileURLWithPath: #filePath)
        let url = testFile
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
        let parser = EPUBParser()

        let parsed = try await parser.parse(fileAt: url)

        XCTAssertEqual(parsed.title, "Minimal Book")
        XCTAssertEqual(parsed.author, "Test Author")
        XCTAssertEqual(parsed.renderer, .html)
        XCTAssertEqual(parsed.chapters.count, 1)
        XCTAssertEqual(parsed.chapters[0].title, "Chapter 1")
        XCTAssertTrue(parsed.chapters[0].bodyHTML.contains("Content of chapter one"))
        XCTAssertEqual(parsed.toc.count, 1)
        XCTAssertEqual(parsed.toc[0].title, "Chapter 1")
        XCTAssertEqual(parsed.toc[0].chapterIndex, 0)
        XCTAssertNotNil(parsed.resourceDirectory)
    }
}
