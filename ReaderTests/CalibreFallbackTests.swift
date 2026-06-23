import SwiftData
import XCTest
@testable import Reader

final class CalibreFallbackTests: XCTestCase {
    /// 直接调用 parseViaCalibre 测试 fallback 路径，避免 /dev/null 权限问题
    func testParseViaCalibreSuccessReturnsParsedBook() async throws {
        let stub = StubMOBIConverter(result: .success(epubFixtureURL()))
        let parser = MOBIParser(converter: stub)

        let parsed = try await parser.testParseViaCalibre(fileAt: URL(fileURLWithPath: "/tmp/ignored"))
        XCTAssertEqual(parsed.title, "Minimal Book")
    }

    func testParseViaCalibreThrowsWhenNotInstalled() async {
        let stub = StubMOBIConverter(result: .failure(BookParseError.calibreNotInstalled))
        let parser = MOBIParser(converter: stub)

        do {
            _ = try await parser.testParseViaCalibre(fileAt: URL(fileURLWithPath: "/tmp/ignored"))
            XCTFail("应抛错")
        } catch BookParseError.calibreNotInstalled {
            // 通过
        } catch {
            XCTFail("错误类型不对：\(error)")
        }
    }

    private func epubFixtureURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .appendingPathComponent("Fixtures/minimal.epub")
    }
}

final class BookLibraryTests: XCTestCase {
    @MainActor
    func testDeleteBookRemovesRecordAndImportedFile() throws {
        let container = try ModelContainer(
            for: Book.self, Bookmark.self, Highlight.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
        let storage = StorageService(modelContext: container.mainContext)
        let appSupport = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let library = BookLibrary(storageService: storage, appSupportDirectory: appSupport)
        let source = appSupport.appendingPathComponent("source.pdf")
        try FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
        try Data("fake pdf".utf8).write(to: source)
        defer { try? FileManager.default.removeItem(at: appSupport) }

        let book = try library.importBook(at: source)
        XCTAssertTrue(FileManager.default.fileExists(atPath: book.filePath))

        try library.deleteBook(book)

        XCTAssertTrue(storage.fetchBooks().isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: book.filePath))
    }
}

final class StubMOBIConverter: MOBIConverting {
    enum Result {
        case success(URL)
        case failure(Error)
    }
    let result: Result
    let isAvailable: Bool = true
    init(result: Result) { self.result = result }

    func convertToEPUB(mobiURL: URL) async throws -> URL {
        switch result {
        case .success(let url): return url
        case .failure(let err): throw err
        }
    }
}
